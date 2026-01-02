/*
 * modeset - DRM Modesetting Example
 *
 * Written 2012-2013 by David Herrmann <dh.herrmann@googlemail.com>
 * Dedicated to the Public Domain.
 */

/*
 * Modesetting Example
 * This example is based on:
 *   https://github.com/dvdhrm/docs/blob/master/drm-howto/modeset.c
 *
 * What does it do?
 *   It opens a single DRM-card device node, assigns a CRTC+encoder to each
 *   connector that is connected and creates a framebuffer (DRM-dumb buffers)
 *   for each CRTC that is in use.
 *   It then draws a changing color value for 5s on all framebuffers and exits.
 */

#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <xf86drm.h>
#include <xf86drmMode.h>
#include <libdrm/drm.h>

struct modeset_dev {
    struct modeset_dev *next;

    uint32_t width;
    uint32_t height;
    uint32_t stride;
    uint32_t size;
    uint32_t handle;
    uint8_t *map;

    /* Second buffer for double buffering */
    uint32_t size2;
    uint32_t handle2;
    uint8_t *map2;

    drmModeModeInfo mode;
    uint32_t fb;
    uint32_t fb2;  /* Second framebuffer for double buffering */
    uint32_t conn;
    uint32_t crtc;
    uint32_t plane;  /* Primary plane for this CRTC */
    drmModeCrtc *saved_crtc;

    /* Property IDs for atomic modesetting */
    uint32_t conn_crtc_id_prop;
    uint32_t crtc_active_prop;
    uint32_t crtc_mode_id_prop;
    uint32_t plane_crtc_id_prop;
    uint32_t plane_fb_id_prop;
    uint32_t plane_crtc_x_prop;
    uint32_t plane_crtc_y_prop;
    uint32_t plane_crtc_w_prop;
    uint32_t plane_crtc_h_prop;
    uint32_t plane_src_x_prop;
    uint32_t plane_src_y_prop;
    uint32_t plane_src_w_prop;
    uint32_t plane_src_h_prop;

    uint32_t mode_blob_id;
    int current_fb;  /* 0 or 1 for double buffering */
    bool pflip_pending;
};

static struct modeset_dev *modeset_list = NULL;

static uint32_t get_property_id(int fd, drmModeObjectProperties *props,
                                 const char *name)
{
    drmModePropertyRes *prop;
    uint32_t i, id = 0;

    for (i = 0; i < props->count_props; i++) {
        prop = drmModeGetProperty(fd, props->props[i]);
        if (!prop)
            continue;

        if (strcmp(prop->name, name) == 0)
            id = prop->prop_id;

        drmModeFreeProperty(prop);
        if (id)
            break;
    }

    return id;
}

static int get_properties(int fd, uint32_t obj_id, uint32_t obj_type,
                         struct modeset_dev *dev)
{
    drmModeObjectProperties *props;

    props = drmModeObjectGetProperties(fd, obj_id, obj_type);
    if (!props)
        return -errno;

    if (obj_type == DRM_MODE_OBJECT_CONNECTOR) {
        dev->conn_crtc_id_prop = get_property_id(fd, props, "CRTC_ID");
    } else if (obj_type == DRM_MODE_OBJECT_CRTC) {
        dev->crtc_active_prop = get_property_id(fd, props, "ACTIVE");
        dev->crtc_mode_id_prop = get_property_id(fd, props, "MODE_ID");
    } else if (obj_type == DRM_MODE_OBJECT_PLANE) {
        dev->plane_crtc_id_prop = get_property_id(fd, props, "CRTC_ID");
        dev->plane_fb_id_prop = get_property_id(fd, props, "FB_ID");
        dev->plane_crtc_x_prop = get_property_id(fd, props, "CRTC_X");
        dev->plane_crtc_y_prop = get_property_id(fd, props, "CRTC_Y");
        dev->plane_crtc_w_prop = get_property_id(fd, props, "CRTC_W");
        dev->plane_crtc_h_prop = get_property_id(fd, props, "CRTC_H");
        dev->plane_src_x_prop = get_property_id(fd, props, "SRC_X");
        dev->plane_src_y_prop = get_property_id(fd, props, "SRC_Y");
        dev->plane_src_w_prop = get_property_id(fd, props, "SRC_W");
        dev->plane_src_h_prop = get_property_id(fd, props, "SRC_H");
    }

    drmModeFreeObjectProperties(props);
    return 0;
}

static int modeset_find_crtc(int fd, drmModeRes *res, drmModeConnector *conn,
                 struct modeset_dev *dev)
{
    drmModeEncoder *enc;
    unsigned int i, j;
    int32_t crtc;
    struct modeset_dev *iter;

    /* first try the currently conected encoder+crtc */
    if (conn->encoder_id)
        enc = drmModeGetEncoder(fd, conn->encoder_id);
    else
        enc = NULL;

    if (enc) {
        if (enc->crtc_id) {
            crtc = enc->crtc_id;
            for (iter = modeset_list; iter; iter = iter->next) {
                if (iter->crtc == crtc) {
                    crtc = -1;
                    break;
                }
            }

            if (crtc >= 0) {
                drmModeFreeEncoder(enc);
                dev->crtc = crtc;
                return 0;
            }
        }

        drmModeFreeEncoder(enc);
    }

    /* If the connector is not currently bound to an encoder or if the
     * encoder+crtc is already used by another connector (actually unlikely
     * but lets be safe), iterate all other available encoders to find a
     * matching CRTC. */
    for (i = 0; i < conn->count_encoders; ++i) {
        enc = drmModeGetEncoder(fd, conn->encoders[i]);
        if (!enc) {
            fprintf(stderr, "cannot retrieve encoder %u:%u (%d): %m\n",
                i, conn->encoders[i], errno);
            continue;
        }

        /* iterate all global CRTCs */
        for (j = 0; j < res->count_crtcs; ++j) {
            /* check whether this CRTC works with the encoder */
            if (!(enc->possible_crtcs & (1 << j)))
                continue;

            /* check that no other device already uses this CRTC */
            crtc = res->crtcs[j];
            for (iter = modeset_list; iter; iter = iter->next) {
                if (iter->crtc == crtc) {
                    crtc = -1;
                    break;
                }
            }

            /* we have found a CRTC, so save it and return */
            if (crtc >= 0) {
                drmModeFreeEncoder(enc);
                dev->crtc = crtc;
                return 0;
            }
        }

        drmModeFreeEncoder(enc);
    }

    fprintf(stderr, "cannot find suitable CRTC for connector %u\n",
        conn->connector_id);
    return -ENOENT;
}

static int modeset_create_fb(int fd, struct modeset_dev *dev)
{
    struct drm_mode_create_dumb creq;
    struct drm_mode_destroy_dumb dreq;
    struct drm_mode_map_dumb mreq;
    int ret;

    /* create first dumb buffer */
    memset(&creq, 0, sizeof(creq));
    creq.width = dev->width;
    creq.height = dev->height;
    creq.bpp = 32;
    ret = drmIoctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &creq);
    if (ret < 0) {
        fprintf(stderr, "cannot create dumb buffer (%d): %m\n",
            errno);
        return -errno;
    }
    dev->stride = creq.pitch;
    dev->size = creq.size;
    dev->handle = creq.handle;

    /* create framebuffer object for the first dumb-buffer */
    ret = drmModeAddFB(fd, dev->width, dev->height, 24, 32, dev->stride,
               dev->handle, &dev->fb);
    if (ret) {
        fprintf(stderr, "cannot create framebuffer (%d): %m\n",
            errno);
        ret = -errno;
        goto err_destroy;
    }

    /* prepare first buffer for memory mapping */
    memset(&mreq, 0, sizeof(mreq));
    mreq.handle = dev->handle;
    ret = drmIoctl(fd, DRM_IOCTL_MODE_MAP_DUMB, &mreq);
    if (ret) {
        fprintf(stderr, "cannot map dumb buffer (%d): %m\n",
            errno);
        ret = -errno;
        goto err_fb;
    }

    /* perform actual memory mapping */
    dev->map = mmap(0, dev->size, PROT_READ | PROT_WRITE, MAP_SHARED,
                fd, mreq.offset);
    if (dev->map == MAP_FAILED) {
        fprintf(stderr, "cannot mmap dumb buffer (%d): %m\n",
            errno);
        ret = -errno;
        goto err_fb;
    }

    /* clear the framebuffer to 0 */
    memset(dev->map, 0, dev->size);

    /* create second dumb buffer for double buffering */
    memset(&creq, 0, sizeof(creq));
    creq.width = dev->width;
    creq.height = dev->height;
    creq.bpp = 32;
    ret = drmIoctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &creq);
    if (ret < 0) {
        fprintf(stderr, "cannot create second dumb buffer (%d): %m\n",
            errno);
        ret = -errno;
        goto err_map;
    }
    dev->size2 = creq.size;
    dev->handle2 = creq.handle;

    /* create framebuffer object for the second dumb-buffer */
    ret = drmModeAddFB(fd, dev->width, dev->height, 24, 32, dev->stride,
               dev->handle2, &dev->fb2);
    if (ret) {
        fprintf(stderr, "cannot create second framebuffer (%d): %m\n",
            errno);
        ret = -errno;
        goto err_destroy2;
    }

    /* prepare second buffer for memory mapping */
    memset(&mreq, 0, sizeof(mreq));
    mreq.handle = dev->handle2;
    ret = drmIoctl(fd, DRM_IOCTL_MODE_MAP_DUMB, &mreq);
    if (ret) {
        fprintf(stderr, "cannot map second dumb buffer (%d): %m\n",
            errno);
        ret = -errno;
        goto err_fb2;
    }

    /* perform actual memory mapping for second buffer */
    dev->map2 = mmap(0, dev->size2, PROT_READ | PROT_WRITE, MAP_SHARED,
                fd, mreq.offset);
    if (dev->map2 == MAP_FAILED) {
        fprintf(stderr, "cannot mmap second dumb buffer (%d): %m\n",
            errno);
        ret = -errno;
        goto err_fb2;
    }

    /* clear the second framebuffer to 0 */
    memset(dev->map2, 0, dev->size2);

    dev->current_fb = 0;

    return 0;

err_fb2:
    drmModeRmFB(fd, dev->fb2);
err_destroy2:
    memset(&dreq, 0, sizeof(dreq));
    dreq.handle = dev->handle2;
    drmIoctl(fd, DRM_IOCTL_MODE_DESTROY_DUMB, &dreq);
err_map:
    munmap(dev->map, dev->size);
err_fb:
    drmModeRmFB(fd, dev->fb);
err_destroy:
    memset(&dreq, 0, sizeof(dreq));
    dreq.handle = dev->handle;
    drmIoctl(fd, DRM_IOCTL_MODE_DESTROY_DUMB, &dreq);
    return ret;
}

static int modeset_find_plane(int fd, struct modeset_dev *dev)
{
    drmModePlaneResPtr plane_res;
    bool found = false;
    uint32_t i;

    plane_res = drmModeGetPlaneResources(fd);
    if (!plane_res) {
        fprintf(stderr, "drmModeGetPlaneResources failed: %m\n");
        return -errno;
    }

    for (i = 0; i < plane_res->count_planes; i++) {
        drmModePlanePtr plane = drmModeGetPlane(fd, plane_res->planes[i]);
        if (!plane) {
            fprintf(stderr, "drmModeGetPlane failed: %m\n");
            continue;
        }

        if (plane->possible_crtcs & (1 << 0)) {
            /* Check if this is the primary plane for our CRTC */
            drmModeObjectPropertiesPtr props =
                drmModeObjectGetProperties(fd, plane->plane_id,
                                         DRM_MODE_OBJECT_PLANE);
            if (props) {
                uint32_t j;
                for (j = 0; j < props->count_props; j++) {
                    drmModePropertyPtr prop =
                        drmModeGetProperty(fd, props->props[j]);
                    if (prop && strcmp(prop->name, "type") == 0 &&
                        props->prop_values[j] == DRM_PLANE_TYPE_PRIMARY) {
                        if (plane->possible_crtcs & (1 << 0)) {
                            dev->plane = plane->plane_id;
                            found = true;
                        }
                        drmModeFreeProperty(prop);
                        break;
                    }
                    if (prop)
                        drmModeFreeProperty(prop);
                }
                drmModeFreeObjectProperties(props);
            }
        }

        drmModeFreePlane(plane);
        if (found)
            break;
    }

    drmModeFreePlaneResources(plane_res);

    if (!found) {
        fprintf(stderr, "could not find primary plane\n");
        return -ENOENT;
    }

    return 0;
}

static int modeset_setup_dev(int fd, drmModeRes *res, drmModeConnector *conn,
                 struct modeset_dev *dev)
{
    int ret;

    /* check if a monitor is connected */
    if (conn->connection != DRM_MODE_CONNECTED) {
        fprintf(stderr, "ignoring unused connector %u\n",
            conn->connector_id);
        return -ENOENT;
    }

    /* check if there is at least one valid mode */
    if (conn->count_modes == 0) {
        fprintf(stderr, "no valid mode for connector %u\n",
            conn->connector_id);
        return -EFAULT;
    }

    /* copy the mode information into our device structure */
    memcpy(&dev->mode, &conn->modes[0], sizeof(dev->mode));
    dev->width = conn->modes[0].hdisplay;
    dev->height = conn->modes[0].vdisplay;
    fprintf(stderr, "mode for connector %u is %ux%u\n",
        conn->connector_id, dev->width, dev->height);

    /* find a crtc for this connector */
    ret = modeset_find_crtc(fd, res, conn, dev);
    if (ret) {
        fprintf(stderr, "no valid crtc for connector %u\n",
            conn->connector_id);
        return ret;
    }

    /* create a framebuffer for this CRTC */
    ret = modeset_create_fb(fd, dev);
    if (ret) {
        fprintf(stderr, "cannot create framebuffer for connector %u\n",
            conn->connector_id);
        return ret;
    }

    /* get properties for atomic modesetting */
    ret = get_properties(fd, conn->connector_id, DRM_MODE_OBJECT_CONNECTOR, dev);
    if (ret) {
        fprintf(stderr, "cannot get connector properties\n");
        return ret;
    }

    ret = get_properties(fd, dev->crtc, DRM_MODE_OBJECT_CRTC, dev);
    if (ret) {
        fprintf(stderr, "cannot get CRTC properties\n");
        return ret;
    }

    /* find primary plane for this CRTC */
    ret = modeset_find_plane(fd, dev);
    if (ret) {
        fprintf(stderr, "cannot find plane for CRTC\n");
        return ret;
    }

    ret = get_properties(fd, dev->plane, DRM_MODE_OBJECT_PLANE, dev);
    if (ret) {
        fprintf(stderr, "cannot get plane properties\n");
        return ret;
    }

    return 0;
}

static int modeset_prepare(int fd)
{
    drmModeRes *res;
    drmModeConnector *conn;
    unsigned int i;
    struct modeset_dev *dev;
    int ret;

    /* retrieve resources */
    res = drmModeGetResources(fd);
    if (!res) {
        fprintf(stderr, "cannot retrieve DRM resources (%d): %m\n",
            errno);
        return -errno;
    }

    /* iterate all connectors */
    for (i = 0; i < res->count_connectors; ++i) {
        /* get information for each connector */
        conn = drmModeGetConnector(fd, res->connectors[i]);
        if (!conn) {
            fprintf(stderr, "cannot retrieve DRM connector %u:%u (%d): %m\n",
                i, res->connectors[i], errno);
            continue;
        }

        /* create a device structure */
        dev = malloc(sizeof(*dev));
        memset(dev, 0, sizeof(*dev));
        dev->conn = conn->connector_id;

        /* call helper function to prepare this connector */
        ret = modeset_setup_dev(fd, res, conn, dev);
        if (ret) {
            if (ret != -ENOENT) {
                errno = -ret;
                fprintf(stderr, "cannot setup device for connector %u:%u (%d): %m\n",
                    i, res->connectors[i], errno);
            }
            free(dev);
            drmModeFreeConnector(conn);
            continue;
        }

        /* free connector data and link device into global list */
        drmModeFreeConnector(conn);
        dev->next = modeset_list;
        modeset_list = dev;
    }

    /* free resources again */
    drmModeFreeResources(res);
    return 0;
}

static uint8_t next_color(bool *up, uint8_t cur, unsigned int mod)
{
    uint8_t next;

    next = cur + (*up ? 1 : -1) * (rand() % mod);
    if ((*up && next < cur) || (!*up && next > cur)) {
        *up = !*up;
        next = cur;
    }

    return next;
}

static int modeset_open(int *out, const char *node)
{
    int fd, ret;
    uint64_t has_dumb;

    fd = open(node, O_RDWR | O_CLOEXEC);
    if (fd < 0) {
        ret = -errno;
        fprintf(stderr, "cannot open '%s': %m\n", node);
        return ret;
    }

    if (drmGetCap(fd, DRM_CAP_DUMB_BUFFER, &has_dumb) < 0 ||
        !has_dumb) {
        fprintf(stderr, "drm device '%s' does not support dumb buffers\n",
            node);
        close(fd);
        return -EOPNOTSUPP;
    }

    *out = fd;
    return 0;
}

static void page_flip_handler(int fd, unsigned int frame,
                              unsigned int sec, unsigned int usec,
                              void *data)
{
    struct modeset_dev *dev = data;
    dev->pflip_pending = false;
}

static void modeset_draw(int fd)
{
    uint8_t r, g, b;
    bool r_up, g_up, b_up;
    unsigned int i, j, k, off;
    struct modeset_dev *iter;
    drmEventContext ev;
    fd_set fds;
    int ret;

    memset(&ev, 0, sizeof(ev));
    ev.version = 2;
    ev.page_flip_handler = page_flip_handler;

    srand(time(NULL));
    r = rand() % 0xff;
    g = rand() % 0xff;
    b = rand() % 0xff;
    r_up = g_up = b_up = true;

    for (i = 0; i < 50; ++i) {
        r = next_color(&r_up, r, 20);
        g = next_color(&g_up, g, 10);
        b = next_color(&b_up, b, 5);

        /* Draw to back buffer for each device */
        for (iter = modeset_list; iter; iter = iter->next) {
            uint8_t *back_buffer = iter->current_fb == 0 ? iter->map2 : iter->map;

            for (j = 0; j < iter->height; ++j) {
                for (k = 0; k < iter->width; ++k) {
                    off = iter->stride * j + k * 4;
                    *(uint32_t*)&back_buffer[off] = (r << 16) | (g << 8) | b;
                }
            }
        }

        /* Queue page flip for each device */
        for (iter = modeset_list; iter; iter = iter->next) {
            uint32_t fb = iter->current_fb == 0 ? iter->fb2 : iter->fb;

            ret = drmModePageFlip(fd, iter->crtc, fb,
                                DRM_MODE_PAGE_FLIP_EVENT, iter);
            if (ret) {
                fprintf(stderr, "cannot flip CRTC for connector %u (%d): %m\n",
                    iter->conn, errno);
            } else {
                iter->pflip_pending = true;
                iter->current_fb = 1 - iter->current_fb;
            }
        }

        /* Wait for all page flips to complete */
        while (1) {
            bool pending = false;
            for (iter = modeset_list; iter; iter = iter->next) {
                if (iter->pflip_pending) {
                    pending = true;
                    break;
                }
            }
            if (!pending)
                break;

            FD_ZERO(&fds);
            FD_SET(fd, &fds);

            ret = select(fd + 1, &fds, NULL, NULL, NULL);
            if (ret < 0) {
                fprintf(stderr, "select failed: %m\n");
                break;
            } else if (ret == 0) {
                fprintf(stderr, "select timeout\n");
                break;
            } else if (FD_ISSET(fd, &fds)) {
                drmHandleEvent(fd, &ev);
            }
        }

        usleep(100000);
    }
}

static void modeset_cleanup(int fd)
{
    struct modeset_dev *iter;
    struct drm_mode_destroy_dumb dreq;

    while (modeset_list) {
        /* remove from global list */
        iter = modeset_list;
        modeset_list = iter->next;

        /* restore saved CRTC configuration */
        drmModeSetCrtc(fd,
                   iter->saved_crtc->crtc_id,
                   iter->saved_crtc->buffer_id,
                   iter->saved_crtc->x,
                   iter->saved_crtc->y,
                   &iter->conn,
                   1,
                   &iter->saved_crtc->mode);
        drmModeFreeCrtc(iter->saved_crtc);

        /* Destroy mode blob if created */
        if (iter->mode_blob_id)
            drmModeDestroyPropertyBlob(fd, iter->mode_blob_id);

        /* Cleanup first framebuffer */
        munmap(iter->map, iter->size);
        drmModeRmFB(fd, iter->fb);

        memset(&dreq, 0, sizeof(dreq));
        dreq.handle = iter->handle;
        drmIoctl(fd, DRM_IOCTL_MODE_DESTROY_DUMB, &dreq);

        /* Cleanup second framebuffer */
        munmap(iter->map2, iter->size2);
        drmModeRmFB(fd, iter->fb2);

        memset(&dreq, 0, sizeof(dreq));
        dreq.handle = iter->handle2;
        drmIoctl(fd, DRM_IOCTL_MODE_DESTROY_DUMB, &dreq);

        free(iter);
    }
}

int main(int argc, char **argv)
{
    int ret, fd;
    const char *card;
    struct modeset_dev *iter;
    uint64_t has_atomic;

    if (argc > 1)
        card = argv[1];
    else
        card = DRM_DIR_NAME "/" DRM_PRIMARY_MINOR_NAME "0";

    fprintf(stderr, "using card '%s'\n", card);

    /* open the DRM device */
    ret = modeset_open(&fd, card);
    if (ret)
        goto out_return;

    /* enable universal planes (required for atomic) */
    ret = drmSetClientCap(fd, DRM_CLIENT_CAP_UNIVERSAL_PLANES, 1);
    if (ret) {
        fprintf(stderr, "failed to enable universal planes\n");
        goto out_close;
    }

    /* enable atomic modesetting */
    ret = drmSetClientCap(fd, DRM_CLIENT_CAP_ATOMIC, 1);
    if (ret) {
        fprintf(stderr, "failed to enable atomic modesetting\n");
        goto out_close;
    }

    /* prepare all connectors and CRTCs */
    ret = modeset_prepare(fd);
    if (ret)
        goto out_close;

    /* perform atomic modesetting on each found connector+CRTC */
    for (iter = modeset_list; iter; iter = iter->next) {
        drmModeAtomicReqPtr req;
        uint32_t flags = DRM_MODE_ATOMIC_ALLOW_MODESET;

        iter->saved_crtc = drmModeGetCrtc(fd, iter->crtc);

        /* Create mode blob */
        ret = drmModeCreatePropertyBlob(fd, &iter->mode,
                                       sizeof(iter->mode),
                                       &iter->mode_blob_id);
        if (ret) {
            fprintf(stderr, "cannot create mode blob: %m\n");
            continue;
        }

        /* Build atomic request */
        req = drmModeAtomicAlloc();
        if (!req) {
            fprintf(stderr, "cannot allocate atomic request\n");
            continue;
        }

        /* Set connector CRTC */
        drmModeAtomicAddProperty(req, iter->conn, iter->conn_crtc_id_prop,
                                iter->crtc);

        /* Set CRTC mode and active */
        drmModeAtomicAddProperty(req, iter->crtc, iter->crtc_active_prop, 1);
        drmModeAtomicAddProperty(req, iter->crtc, iter->crtc_mode_id_prop,
                                iter->mode_blob_id);

        /* Set plane properties */
        drmModeAtomicAddProperty(req, iter->plane, iter->plane_fb_id_prop,
                                iter->fb);
        drmModeAtomicAddProperty(req, iter->plane, iter->plane_crtc_id_prop,
                                iter->crtc);
        drmModeAtomicAddProperty(req, iter->plane, iter->plane_crtc_x_prop, 0);
        drmModeAtomicAddProperty(req, iter->plane, iter->plane_crtc_y_prop, 0);
        drmModeAtomicAddProperty(req, iter->plane, iter->plane_crtc_w_prop,
                                iter->width);
        drmModeAtomicAddProperty(req, iter->plane, iter->plane_crtc_h_prop,
                                iter->height);
        drmModeAtomicAddProperty(req, iter->plane, iter->plane_src_x_prop, 0);
        drmModeAtomicAddProperty(req, iter->plane, iter->plane_src_y_prop, 0);
        drmModeAtomicAddProperty(req, iter->plane, iter->plane_src_w_prop,
                                iter->width << 16);
        drmModeAtomicAddProperty(req, iter->plane, iter->plane_src_h_prop,
                                iter->height << 16);

        /* Commit the atomic request */
        ret = drmModeAtomicCommit(fd, req, flags, NULL);
        if (ret) {
            fprintf(stderr, "cannot set atomic mode for connector %u (%d): %m\n",
                iter->conn, errno);
        }

        drmModeAtomicFree(req);
    }

    /* draw some colors for 5 seconds using page flips */
    modeset_draw(fd);

    modeset_cleanup(fd);

    ret = 0;

out_close:
    close(fd);
out_return:
    if (ret) {
        errno = -ret;
        fprintf(stderr, "modeset failed with error %d: %m\n", errno);
    } else {
        fprintf(stderr, "exiting\n");
    }
    return ret;
}

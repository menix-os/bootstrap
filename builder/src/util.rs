use anyhow::Context;
use decompress::ExtractOptsBuilder;
use std::{
    env,
    fs::{self, File},
    io::{self, Write},
    path::{Path, PathBuf},
    process::{Command, Stdio},
};

use crate::{Args, Package};

pub fn run_command(mut command: Command) -> anyhow::Result<()> {
    let output = command
        .output()
        .context(format!("failed to run command: {:?}", command))?;

    if !output.status.success() {
        anyhow::bail!(
            "failed to run {:?}: exited with status {}:\nstderr:\n{}\nstdout:\n{}",
            command,
            output.status,
            String::from_utf8(output.stdout)?,
            String::from_utf8(output.stderr)?
        );
    }

    Ok(())
}

// TODO: Redirect stdout, stderr and only print it on child process failure.
pub fn run_command_stdin(command: &mut Command, stdin_data: &[u8]) -> anyhow::Result<()> {
    command.stdin(Stdio::piped());

    let mut child = command
        .spawn()
        .context(format!("failed to spawn {:?}", command))?;

    if let Some(ref mut stdin) = child.stdin {
        stdin
            .write_all(stdin_data)
            .context(format!("failed to write stdin of {:?}", command))?;
    } else {
        anyhow::bail!("failed to find stdin of {:?}", command);
    }

    let status = child
        .wait()
        .context(format!("failed to run {:?}", command))?;

    if !status.success() {
        anyhow::bail!("failed to run {:?}: exited with status {}", command, status)
    }

    Ok(())
}

pub fn resolve_path(path: &Path, base_dir: &Path) -> PathBuf {
    // handle absolute and relative paths
    if path.is_absolute() {
        path.to_owned()
    } else {
        base_dir.join(path)
    }
}

pub fn copy_dir_all(src: impl AsRef<Path>, dst: impl AsRef<Path>) -> io::Result<()> {
    fs::create_dir_all(&dst)?;
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let ty = entry.file_type()?;
        if ty.is_dir() {
            copy_dir_all(entry.path(), dst.as_ref().join(entry.file_name()))?;
        } else {
            fs::copy(entry.path(), dst.as_ref().join(entry.file_name()))?;
        }
    }
    Ok(())
}

/// Like the linux `touch` command
pub fn touch(file: &Path) -> anyhow::Result<()> {
    if file.exists() {
        fs::remove_file(file)?;
    }
    File::options()
        .create(true)
        .write(true)
        .open(file)
        .context("Failed to open file")
        .map(|_| ())
}

pub fn decompress_archive(archive: &Path, decompress_to: &Path) -> anyhow::Result<()> {
    decompress::decompress(
        &archive,
        &decompress_to,
        &ExtractOptsBuilder::default()
            .build()
            .expect("Default compress builder should always work"),
    )
    .context("Failed to decompress archive")?;

    Ok(())
}

pub fn determine_if_step_needed(pkg_path: &Path, marker: &Path) -> anyhow::Result<bool> {
    let pkg_meta = match pkg_path.metadata() {
        Ok(x) => x,
        Err(_) => return Ok(true),
    };

    if let Ok(marker_meta) = marker.metadata() {
        if pkg_meta.modified()? > marker_meta.modified()? {
            Ok(true)
        } else {
            Ok(false)
        }
    } else {
        Ok(true)
    }
}

pub fn check_host_program<P>(exe_name: P) -> Option<PathBuf>
where
    P: AsRef<Path>,
{
    env::var_os("PATH").and_then(|paths| {
        env::split_paths(&paths)
            .filter_map(|dir| {
                let full_path = dir.join(&exe_name);
                if full_path.is_file() {
                    Some(full_path)
                } else {
                    None
                }
            })
            .next()
    })
}

pub fn add_env_to_cmd(cmd: &mut Command, package: &Package, args: &Args) -> anyhow::Result<()> {
    cmd.env(
        "SOURCE_DIR",
        &args.source_path.canonicalize()?.join(&package.package.name),
    );
    cmd.env(
        "BUILD_DIR",
        &args.build_path.canonicalize()?.join(&package.package.name),
    );
    cmd.env("INSTALL_DIR", &args.install_path.canonicalize()?);
    cmd.env("IS_DEBUG", if args.debug { "1" } else { "0" });
    cmd.env("CFLAGS", if args.debug { "-O0 -g" } else { "-O3" });
    cmd.env("OS_TRIPLET", args.target.clone() + "-pc-menix");
    cmd.env("THREADS", "12"); // TODO
    cmd.env("PREFIX", "/usr");
    cmd.env("PREFIX_HOST", "/usr/local");

    Ok(())
}

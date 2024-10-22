use anyhow::Context;
use serde::Deserialize;
use std::{
    env,
    fs::{self, File},
    io::{self, Write},
    path::{Path, PathBuf},
    process::{Command, Stdio},
    thread::available_parallelism,
};

use crate::Args;

#[derive(Deserialize, Clone, Debug)]
pub struct Package {
    pub package: PackageInfo,
    #[serde(default)]
    pub sources: Vec<PackageSource>,
    pub dependencies: Option<PackageDeps>,
    pub configure: Option<PackageScript>,
    pub build: Option<PackageScript>,
    pub install: Option<PackageScript>,
}

#[derive(Deserialize, Clone, Debug)]
pub struct PackageInfo {
    pub name: String,
    pub version: String,
    pub archs: Vec<String>,
    #[serde(default)]
    pub host: bool,
    pub shared_source: Option<PathBuf>,
    pub shared_build: Option<PathBuf>,
}

#[derive(Deserialize, Clone, Debug)]
pub struct PackageDeps {
    #[serde(default)]
    pub build: Vec<String>,
    #[serde(default)]
    pub host: Vec<String>,
    #[serde(default)]
    pub runtime: Vec<String>,
}

#[derive(Deserialize, Clone, Debug)]
pub struct PackageSource {
    #[serde(flatten)]
    pub source: PackageSourceType,
    #[serde(default)]
    pub patches: Vec<PathBuf>,
}

#[derive(Deserialize, Clone, Debug)]
#[serde(untagged)]
pub enum PackageSourceType {
    Archive {
        archive: PathBuf,
    },
    RemoteArchive {
        url: PathBuf,
        path: PathBuf,
    },
    Git {
        repo: String,
        branch: Option<String>,
        path: Option<PathBuf>,
    },
    Local {
        path: PathBuf,
    },
}

#[derive(Deserialize, Clone, Debug)]
pub struct PackageScript {
    pub script: String,
}

pub fn run_command(mut command: Command) -> anyhow::Result<()> {
    let mut child = command
        .spawn()
        .context(format!("failed to run command: {:?}", command))?;

    let status = child
        .wait()
        .context(format!("failed to run {:?}", command))?;

    if !status.success() {
        anyhow::bail!("failed to run {:?}: exited with status {}", command, status,);
    }

    Ok(())
}

pub fn run_command_stdin(command: &mut Command, stdin_data: &[u8]) -> anyhow::Result<()> {
    command.stdin(Stdio::piped());

    let mut child = command
        .spawn()
        .context(format!("failed to spawn {:?}", command))?;

    if let Some(ref mut stdin) = child.stdin {
        stdin
            .write_all(include_bytes!("context.sh"))
            .context(format!("failed to write stdin of {:?}", command))?;
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

pub fn do_git_clone(
    branch: &Option<String>,
    repo: &String,
    source_path: &PathBuf,
) -> anyhow::Result<()> {
    let mut clone_cmd = Command::new("git");
    clone_cmd.arg("clone");

    if let Some(branch_name) = branch {
        clone_cmd.args(vec!["--branch", branch_name]);
    }

    clone_cmd.arg(repo).arg(&source_path);
    run_command(clone_cmd).context("Failed to clone package repository")?;

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
    match &package.package.shared_source {
        Some(x) => {
            cmd.env("SOURCE_DIR", &args.source_path.canonicalize()?.join(x));
        }
        None => {
            cmd.env(
                "SOURCE_DIR",
                &args.source_path.canonicalize()?.join(&package.package.name),
            );
        }
    }

    match &package.package.shared_build {
        Some(x) => {
            cmd.env("BUILD_DIR", &args.build_path.canonicalize()?.join(x));
        }
        None => {
            cmd.env(
                "BUILD_DIR",
                &args.build_path.canonicalize()?.join(&package.package.name),
            );
        }
    }

    cmd.env("SUPPORT_DIR", &args.support.canonicalize()?);
    cmd.env(
        "PACKAGE_DIR",
        &args.path.join(&package.package.name).canonicalize()?,
    );

    if package.package.host {
        cmd.env("INSTALL_DIR", &args.host_path.canonicalize()?);
        cmd.env("IS_HOST_BUILD", "1");
    } else {
        cmd.env("INSTALL_DIR", &args.install_path.canonicalize()?);
    }

    cmd.env("SYSROOT_DIR", &args.install_path.canonicalize()?);
    cmd.env("HOST_DIR", &args.host_path.canonicalize()?);
    cmd.env("IS_DEBUG", if args.debug { "1" } else { "0" });
    cmd.env("ARCH", &args.arch);
    let threads = available_parallelism().unwrap().get();
    cmd.env(
        "THREADS",
        format!("{}", if args.jobs == 0 { threads } else { args.jobs }),
    );

    Ok(())
}

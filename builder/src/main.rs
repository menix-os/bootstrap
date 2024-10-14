use anyhow::Context;
use clap::{Parser, Subcommand};
use serde::Deserialize;
use std::{
    fs::{self},
    path::{Path, PathBuf},
    process::Command,
};
use util::{
    add_env_to_cmd, copy_dir_all, decompress_archive, determine_if_step_needed, resolve_path,
    run_command, run_command_stdin, touch,
};

mod util;

#[derive(Parser, Debug)]
#[command(version)]
struct Args {
    /// Build all packages in `path`.
    #[arg(long, default_value = "true")]
    all: bool,

    /// If false, env_release.sh is used, otherwise env_debug.sh
    #[arg(long)]
    debug: bool,

    /// Target install path.
    #[arg(long, default_value = "build/install")]
    install_path: PathBuf,

    /// Target install path.
    #[arg(long, default_value = "build/build")]
    build_path: PathBuf,

    /// Directory where to store downloaded sources.
    #[arg(long, default_value = "build/source")]
    source_path: PathBuf,

    /// Target architecture.
    #[arg(long, default_value = std::env::consts::ARCH)]
    target: String,

    /// Path to the package(s) to build.
    #[arg(long, default_value = "pkg")]
    path: PathBuf,

    /// The operation to perform.
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand, Debug, PartialEq)]
enum Commands {
    /// Pulls the sources for the given package(s).
    Source,
    /// Builds the given package(s).
    Build,
    /// Build all packages where something changed.
    Install,
}

#[derive(Deserialize, Clone, Debug)]
struct Package {
    package: PackageInfo,
    #[serde(default)]
    sources: Vec<PackageSource>,
    build: PackageScript,
    install: PackageScript,
}

#[derive(Deserialize, Clone, Debug)]
struct PackageInfo {
    name: String,
    version: String,
    archs: Vec<String>,
}

#[derive(Deserialize, Clone, Debug)]
#[serde(untagged)]
enum PackageSource {
    Archive {
        archive: PathBuf,
    },
    Git {
        repo: String,
        branch: Option<String>,
    },
    Local {
        path: PathBuf,
    },
}

#[derive(Deserialize, Clone, Debug)]
struct PackageScript {
    script: String,
}

fn main() -> anyhow::Result<()> {
    let args = Args::parse();

    if args.all {
        // Build all packages in the path directory.
        for entry in args
            .path
            .read_dir()
            .context("Failed to read target directory")?
        {
            let entry = entry.context("Failed to read target directory entry")?;
            let file_type = entry
                .file_type()
                .context("Failed to stat target dir entry")?;
            if file_type.is_dir() {
                let path = entry.path();
                try_run_make_pkg(&args, &path)?;
            }
        }
    } else {
        try_run_make_pkg(&args, &args.path)?;
    }

    Ok(())
}

/// `base_dir` must be the package dir, not the package file
fn step_source(args: &Args, base_dir: &Path, package: &Package) -> anyhow::Result<()> {
    let source_path = args.source_path.join(&package.package.name);

    for source in &package.sources {
        match source {
            PackageSource::Git { repo, branch } => {
                let mut clone_cmd = Command::new("git");
                clone_cmd.arg("clone");

                if let Some(branch_name) = branch {
                    clone_cmd.args(vec!["--branch", branch_name]);
                }

                clone_cmd.arg(repo).arg(&source_path);
                run_command(clone_cmd).context("Failed to clone package repository")?;
            }
            PackageSource::Archive {
                archive: archive_path,
            } => {
                let archive_path = resolve_path(&archive_path, base_dir);

                decompress_archive(&archive_path, &source_path)
                    .context(format!("Failed to open archive: {:?}", archive_path))?;
            }
            PackageSource::Local { path: local_path } => {
                let local_path = resolve_path(&local_path, base_dir);

                copy_dir_all(local_path, &source_path)
                    .context("Failed to copy local directory to build directory")?;
            }
        }
    }
    Ok(())
}

/// Builds a package from the source directory to the build dir.
fn step_build(args: &Args, package: &Package) -> anyhow::Result<()> {
    let mut build_cmd = Command::new("bash");
    build_cmd.current_dir(args.source_path.join(&package.package.name));
    add_env_to_cmd(&mut build_cmd, args)?;

    run_command_stdin(&mut build_cmd, &package.build.script.as_bytes())?;
    Ok(())
}

/// Installs a package from the build directory to the install dir.
fn step_install(args: &Args, package: &Package) -> anyhow::Result<()> {
    let mut install_cmd = Command::new("bash");
    install_cmd.current_dir(args.build_path.join(&package.package.name));
    add_env_to_cmd(&mut install_cmd, args)?;

    run_command_stdin(&mut install_cmd, &package.install.script.as_bytes())?;
    Ok(())
}

fn make_pkg(args: &Args, path: &Path) -> anyhow::Result<()> {
    let (pkg_base_dir, pkg_file_path) = if path.is_dir() {
        (path.to_owned(), path.join("pkg.toml"))
    } else {
        (
            path.parent()
                .map(|x| x.to_owned())
                // If the path has no parent (we are in the same dir as the pkg file) we set `.` as the base dir
                .unwrap_or(PathBuf::from(".")),
            path.to_owned(),
        )
    };

    let package_file = fs::read_to_string(&pkg_file_path).context("Failed to read package file")?;
    let package =
        toml::from_str::<Package>(&package_file).context("Failed to deserialize package file")?;

    // Check if the package is architecture dependent. If yes, check if we're targeting this architecture.
    if !package.package.archs.is_empty() && !package.package.archs.contains(&args.target) {
        anyhow::bail!("Arch not targeted");
    }

    let source_path = args.source_path.join(&package.package.name);
    fs::create_dir_all(&source_path)?;
    let source_path = source_path.canonicalize()?;

    let build_path = args.build_path.join(&package.package.name);
    fs::create_dir_all(&build_path)?;

    // This is redundant most of the time, but in the case it isn't, create the install dir.
    fs::create_dir_all(&args.install_path)?;

    let source_marker_path = source_path.join(".source");
    let build_marker_path = source_path.join(".build");

    let pkg_path = &pkg_base_dir.join("pkg.toml");

    // Get source files.
    if !source_marker_path.exists() || args.command == Commands::Source {
        println!("[{}]\tGetting sources", &package.package.name);
        fs::remove_dir_all(&source_path).context("Failed to remove existing dir")?;
        step_source(args, &source_path, &package)?;
        touch(&source_marker_path).context("Failed to update source marker file (.source)")?;
    }

    // Build package.
    if determine_if_step_needed(&pkg_path, &build_marker_path)? || args.command == Commands::Build {
        println!("[{}]\tBuilding package", &package.package.name);
        step_build(args, &package)?;
        touch(&build_marker_path).context("Failed to update source marker file (.build)")?;

        // Install package to build root.
        println!("[{}]\tInstalling to sysroot", &package.package.name);
        step_install(args, &package)?;
    } else {
        println!("[{}]\tAlready up to date", package.package.name);
    }

    println!(
        "[{}]\tBuild finished for version \"{}\"",
        package.package.name, package.package.version
    );

    return Ok(());
}

fn try_run_make_pkg(args: &Args, path: &Path) -> anyhow::Result<()> {
    make_pkg(&args, &path).context(format!("Failed to build package {:?}", &path))
}

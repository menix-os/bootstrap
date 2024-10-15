use anyhow::Context;
use clap::{Parser, Subcommand};
use std::{
    fs::{self},
    os::unix::fs::symlink,
    path::{Path, PathBuf},
    process::Command,
};
use util::{
    add_env_to_cmd, check_host_program, copy_dir_all, decompress_archive, determine_if_step_needed,
    do_git_clone, resolve_path, run_command, run_command_stdin, touch, Package, PackageSourceType,
};

mod util;

#[derive(Parser, Debug)]
#[command(version)]
struct Args {
    /// If set, builds only one package, otherwise build all packages in `path`.
    #[arg(short, long)]
    pkg: Option<PathBuf>,

    /// If set, the DEBUG env variable is set to 1.
    #[arg(long)]
    debug: bool,

    /// Target install path.
    #[arg(short, long, default_value = "build/install")]
    install_path: PathBuf,

    /// Target install path.
    #[arg(long, default_value = "build/build")]
    build_path: PathBuf,

    /// Directory where to store downloaded sources.
    #[arg(long, default_value = "build/source")]
    source_path: PathBuf,

    /// Target architecture.
    #[arg(short, long, default_value = std::env::consts::ARCH)]
    target: String,

    /// Path to the package(s) to build.
    #[arg(long, default_value = "pkg")]
    path: PathBuf,

    /// Path to the base files.
    #[arg(short, long, default_value = "base")]
    base: PathBuf,

    /// Amount of threads to use for compiling.
    #[arg(short, long, default_value = "0")]
    jobs: usize,

    /// The operation to perform.
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand, Debug, PartialEq)]
enum Commands {
    /// Pulls the sources for the given package(s).
    Source,
    /// Reconfigures the given package(s).
    Configure,
    /// Builds the given package(s).
    Build,
    /// Build all packages where something changed.
    Install,
}

fn main() -> anyhow::Result<()> {
    let args = Args::parse();

    if let Some(single_package) = &args.pkg {
        try_run_make_pkg(&args, &args.path.join(single_package))?;
    } else {
        copy_dir_all(&args.base, &args.install_path)?;

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
    }

    Ok(())
}

/// `base_dir` must be the package dir, not the package file
fn step_source(args: &Args, base_dir: &Path, package: &Package) -> anyhow::Result<()> {
    let source_path = args.source_path.join(&package.package.name);
    fs::remove_dir_all(&source_path).context("Failed to remove existing dir")?;

    for source in &package.sources {
        match &source.source {
            PackageSourceType::Git { repo, branch, path } => {
                if let Some(local_path) = path {
                    let symlink_path = base_dir.join(local_path);
                    if !symlink_path.exists() {
                        do_git_clone(branch, repo, &source_path)?;
                    } else {
                        let symlink_path = base_dir.join(local_path).canonicalize()?;
                        symlink(symlink_path, &source_path)
                            .context("Failed to copy local directory to build directory")?;
                    }
                } else {
                    do_git_clone(branch, repo, &source_path)?;
                }
            }
            PackageSourceType::Archive {
                archive: archive_path,
            } => {
                let archive_path = resolve_path(&archive_path, base_dir);

                decompress_archive(&archive_path, &source_path)
                    .context(format!("Failed to open archive: {:?}", archive_path))?;
            }
            PackageSourceType::Local { path: local_path } => {
                let symlink_path = base_dir.join(local_path).canonicalize()?;
                symlink(symlink_path, &source_path)
                    .context("Failed to copy local directory to build directory")?;
            }
        }

        // Apply all patches.
        for patch in &source.patches {
            println!("[{}]\tApplying patch {:?}", &package.package.name, &patch);
            let full_patch_path = base_dir.join(patch);

            let mut cmd = Command::new("git");
            cmd.arg("apply")
                .arg(
                    full_patch_path
                        .canonicalize()
                        .context(format!("Couldn't find patch {:?}", full_patch_path))?,
                )
                .current_dir(&source_path);
            run_command(cmd)?;
        }
    }
    Ok(())
}

/// Configures a package.
fn step_configure(args: &Args, package: &Package) -> anyhow::Result<()> {
    let mut cfg_cmd = Command::new("bash");
    cfg_cmd.current_dir(args.build_path.join(&package.package.name));
    add_env_to_cmd(&mut cfg_cmd, package, args)?;

    if let Some(configure) = &package.configure {
        run_command_stdin(&mut cfg_cmd, configure.script.as_bytes())?;
    }
    Ok(())
}

/// Builds a package from the source directory to the build dir.
fn step_build(args: &Args, package: &Package) -> anyhow::Result<()> {
    let mut build_cmd = Command::new("bash");
    build_cmd.current_dir(args.build_path.join(&package.package.name));
    add_env_to_cmd(&mut build_cmd, package, args)?;

    if let Some(build) = &package.build {
        run_command_stdin(&mut build_cmd, build.script.as_bytes())?;
    }
    Ok(())
}

/// Installs a package from the build directory to the install dir.
fn step_install(args: &Args, package: &Package) -> anyhow::Result<()> {
    let mut install_cmd = Command::new("bash");
    install_cmd.current_dir(args.build_path.join(&package.package.name));
    add_env_to_cmd(&mut install_cmd, package, args)?;

    if let Some(install) = &package.install {
        run_command_stdin(&mut install_cmd, install.script.as_bytes())?;
    }
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

    let build_path = args.build_path.join(&package.package.name);
    fs::create_dir_all(&build_path)?;

    // This is redundant most of the time, but in the case it isn't, create the install dir.
    fs::create_dir_all(&args.install_path)?;

    let source_marker_path = build_path.join(".source");
    let configure_marker_path = build_path.join(".configure");
    let build_marker_path = build_path.join(".build");

    // Get source files.
    if package.sources.len() > 0 {
        if !source_marker_path.exists() || args.command == Commands::Source {
            println!("[{}]\tGetting sources", &package.package.name);
            step_source(args, &pkg_base_dir, &package)?;
            touch(&source_marker_path).context("Failed to update source marker file (.source)")?;
        }
    }

    // Configure package
    if determine_if_step_needed(&pkg_file_path, &configure_marker_path)?
        || args.command == Commands::Configure
        || args.command == Commands::Source
    {
        step_configure(args, &package)?;
        touch(&configure_marker_path)
            .context("Failed to update configure marker file (.configure)")?;
    }

    // Build package.
    if determine_if_step_needed(&pkg_file_path, &build_marker_path)?
        || determine_if_step_needed(&pkg_file_path, &configure_marker_path)?
        || args.command == Commands::Configure
        || args.command == Commands::Build
    {
        for host_dep in &package.dependencies.host {
            check_host_program(host_dep).expect(&format!(
                "Host dependency \"{}\" could not be satisfied.",
                &host_dep
            ));
        }

        for build_dep in &package.dependencies.build {
            try_run_make_pkg(args, &args.path.clone().join(build_dep))?;
        }

        println!("[{}]\tBuilding package", &package.package.name);
        step_build(args, &package)?;
        touch(&build_marker_path).context("Failed to update source marker file (.build)")?;

        // Install package to build root.
        println!("[{}]\tInstalling to sysroot", &package.package.name);
        step_install(args, &package)?;

        println!(
            "[{}]\tBuild finished for version \"{}\"",
            package.package.name, package.package.version
        );

        for runtime_dep in &package.dependencies.runtime {
            try_run_make_pkg(args, &args.path.clone().join(runtime_dep))?;
        }
    } else {
        println!("[{}]\tAlready up to date", package.package.name);
    }

    return Ok(());
}

fn try_run_make_pkg(args: &Args, path: &Path) -> anyhow::Result<()> {
    make_pkg(&args, &path).context(format!("Failed to build package {:?}", &path))
}

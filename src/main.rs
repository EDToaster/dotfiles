use anyhow::bail;
use clap::{Args, Parser};
use colored::Colorize;
use logger::Logger;
use profile::Config;
use std::{
    fs,
    path::{Path, PathBuf},
    process::{Command, Stdio},
};

use crate::{profile::Profile, util::absolutize};

mod logger;
mod profile;
mod util;

#[derive(Debug, Parser)]
#[command(name = "Dotfiles", about = "Installs dotfiles using symlinks")]
enum ProgArgs {
    #[command(alias = "i")]
    Install(InstallArgs),

    /// Adopt an existing dotfile into a profile: move it into the profile
    /// directory, register it in `dotfile.toml` for the current platform, and
    /// replace the original with a symlink.
    Adopt(AdoptArgs),
}

#[derive(Debug, Args)]
struct InstallArgs {
    /// Run all validations and install the files. Omit to run in dryrun mode
    #[arg(short, long)]
    dryrun: bool,

    /// Enable verbose mode
    #[arg(short, long)]
    verbose: bool,

    /// Profile to install
    #[arg()]
    profile: PathBuf,
}

#[derive(Debug, Args)]
struct AdoptArgs {
    /// Profile directory to adopt the file into (the one containing dotfile.toml)
    #[arg(long)]
    profile: PathBuf,

    /// Display name for the new configuration entry
    #[arg(long)]
    name: String,

    /// Path to the existing dotfile to adopt (its current install location)
    #[arg(long)]
    path: String,

    /// Validate and print the intended actions without changing anything
    #[arg(short, long)]
    dryrun: bool,
}

#[derive(Debug, Clone)]
struct Link {
    install_path: PathBuf,
    parent_path: PathBuf,
    target_path: PathBuf,
}

fn validate_process(cmd: &[String]) -> anyhow::Result<()> {
    let cmd_str = cmd.join(" ");
    let proc = Command::new(&cmd[0])
        .args(&cmd[1..])
        .stdout(Stdio::piped())
        .spawn();
    match proc {
        Ok(proc) => {
            if let Ok(output) = proc.wait_with_output() {
                let stdout = String::from_utf8(output.stdout);
                match stdout {
                    Ok(s) => s
                        .lines()
                        .for_each(|l| log::info!("{}", format!("    Stdout: {l}").dimmed())),
                    Err(_) => log::info!("Stdout from validation command was not valid UTF-8"),
                }

                let status = output.status;
                if !status.success() {
                    bail!(
                        "Validation command failed: {cmd_str:?}. Return code was {:?}",
                        status.code()
                    );
                }
            } else {
                bail!("Unable to wait for completion of validation command: {cmd_str:?}");
            }
        }
        Err(e) => {
            bail!("Something went wrong with spawning the validation command: {cmd_str:?}. {e}");
        }
    }
    Ok(())
}

fn validate_config(
    config: &Config,
    profile_base_path: &PathBuf,
    prof: &Profile,
) -> anyhow::Result<Link> {
    log::info!("{} {config}", "Validating".green());

    let mut target_path = profile_base_path.clone();
    target_path.push(&config.path);
    let target_path = absolutize(&target_path.display().to_string());

    // check target path exists
    if !target_path.exists() {
        bail!("Target path {target_path:?} does not exist.");
    }

    // check the install location is specified in the profile
    let install_path = config.get_install_location();
    if let Some(install_path) = install_path {
        let parent_path = install_path.parent();

        // check install location doesn't already have a file
        if install_path.exists() {
            if install_path.is_symlink() {
                log::warn!("Install path exists as a symlink already.");
            } else {
                bail!("Install path already exists as a file. Delete this file and rerun validations if it is safe to do so.");
            }
        }

        // check parent path already exists
        match parent_path {
            None => {
                bail!("Install path does not have a parent directory.");
            }
            Some(parent_path) => {
                if !parent_path.exists() {
                    log::warn!("Install path's parent does not exist. It will be created.");
                }
                // passed validation, add to links
                Ok(Link {
                    install_path: install_path.clone(),
                    parent_path: parent_path.into(),
                    target_path,
                })
            }
        }
    } else {
        bail!(
            "Install path is not specified for platform {}",
            std::env::consts::OS
        );
    }
}

fn validate(profile_base_path: &PathBuf, prof: &Profile) -> anyhow::Result<Vec<Link>> {
    let iter = prof
        .validation_commands
        .iter()
        .cloned()
        .map(|c| (c, false))
        .chain(
            prof.optional_validation_commands
                .iter()
                .cloned()
                .map(|c| (c, true))
                .collect::<Vec<_>>(),
        );

    // Run pre-validation commands on the profile
    for (cmd, optional) in iter {
        let cmd_str = cmd.join(" ");
        log::info!("Spawning validation command (not escaped) {cmd_str:?}",);
        if cmd.is_empty() {
            bail!("Validation command cannot be empty.");
        }

        let res = validate_process(&cmd);

        match res {
            Err(e) if optional => log::warn!("{e}"),
            Err(e) => bail!(e),
            Ok(_) => {}
        }
    }

    let links: Result<Vec<Link>, _> = prof
        .configs
        .iter()
        .map(|c| validate_config(c, profile_base_path, prof))
        .inspect(|r| {
            r.as_ref().inspect_err(|e| log::error!("{e}")).ok();
        })
        // Collect to vec first, because we don't want to short circuit on the first failure
        .collect::<Vec<_>>()
        .into_iter()
        .collect();

    // Consume the error since we logged in the previous line already. Just return a generic error.
    links.map_err(|_| anyhow::anyhow!("There was an error validating the {:?} profile", prof.name))
}

/// Create a symlink from inst to target.
/// Todo: https://doc.rust-lang.org/std/fs/fn.soft_link.html
/// Since this is deprecated, change to platform-dependent implmentation
/// when allowing for whole-directory symlinks.
#[allow(deprecated)]
fn create_symlink(link: &Link) -> anyhow::Result<()> {
    // Make sure parent path exists
    log::info!(
        "Creating parent directory (if needed) {:?}",
        link.parent_path
    );
    fs::create_dir_all(&link.parent_path)?;

    log::info!(
        "Removing existing install location (if needed) {:?}",
        link.install_path
    );
    match fs::remove_file(&link.install_path) {
        _ => {}
    } // ignore error

    log::info!(
        "Creating link {:?} -> {:?}",
        link.install_path,
        link.target_path
    );
    fs::soft_link(&link.target_path, &link.install_path)?;
    Ok(())
}

fn install(links: &[Link]) -> anyhow::Result<()> {
    for link in links {
        create_symlink(link)?;
    }
    Ok(())
}

/// Map the current OS to the `install_location` platform key used in dotfile.toml.
fn platform_key() -> anyhow::Result<&'static str> {
    match std::env::consts::OS {
        "windows" => Ok("windows"),
        "macos" => Ok("macos"),
        "linux" => Ok("linux"),
        other => bail!("Unsupported platform {other:?}. Cannot determine install location key."),
    }
}

/// Move a file, falling back to copy + remove when `rename` fails (e.g. across
/// filesystem boundaries).
fn move_file(from: &Path, to: &Path) -> anyhow::Result<()> {
    if let Some(parent) = to.parent() {
        fs::create_dir_all(parent)?;
    }
    match fs::rename(from, to) {
        Ok(()) => Ok(()),
        Err(_) => {
            fs::copy(from, to)?;
            fs::remove_file(from)?;
            Ok(())
        }
    }
}

fn run_install(opt: InstallArgs) -> anyhow::Result<()> {
    let dotfile_toml_path = opt.profile.join("dotfile.toml");

    log::info!("Parsing config {:?}", dotfile_toml_path);

    let dotfile_toml = fs::read_to_string(&dotfile_toml_path)?;
    let profile: Profile = toml::from_str(&dotfile_toml)?;

    if opt.verbose {
        log::info!("Parsed profile: {profile:#?}");
    }

    let links = validate(&opt.profile, &profile)?;

    if !opt.dryrun {
        install(&links)?;
    }

    Ok(())
}

fn run_adopt(opt: AdoptArgs) -> anyhow::Result<()> {
    let profile_dir = &opt.profile;
    let dotfile_toml_path = profile_dir.join("dotfile.toml");
    let platform = platform_key()?;

    // --- Validation: profile ---
    if !profile_dir.is_dir() {
        bail!("Profile directory {profile_dir:?} does not exist or is not a directory.");
    }
    if !dotfile_toml_path.is_file() {
        bail!("{dotfile_toml_path:?} does not exist. Is this a valid profile?");
    }

    // --- Validation: source file ---
    let source_abs = absolutize(&opt.path);
    if !source_abs.exists() {
        bail!("Source dotfile {source_abs:?} does not exist.");
    }
    let source_meta = fs::symlink_metadata(&source_abs)?;
    if source_meta.file_type().is_symlink() {
        bail!(
            "Source dotfile {source_abs:?} is already a symlink. It may already be managed; refusing to adopt."
        );
    }
    if !source_meta.is_file() {
        bail!("Source dotfile {source_abs:?} is not a regular file. Only files can be adopted.");
    }

    // --- Derive the in-profile relative path (flat, from the file name) ---
    let file_name = source_abs
        .file_name()
        .ok_or_else(|| anyhow::anyhow!("Could not determine a file name from {source_abs:?}"))?;
    let rel_path_str = file_name
        .to_str()
        .ok_or_else(|| anyhow::anyhow!("File name {file_name:?} is not valid UTF-8"))?
        .to_string();
    let target_abs = absolutize(&profile_dir.join(&rel_path_str).display().to_string());

    // --- Validation: no collisions ---
    if target_abs.exists() {
        bail!("A file already exists in the profile at {target_abs:?}. Refusing to overwrite.");
    }
    if target_abs == source_abs {
        bail!("Source and destination are the same path. Nothing to adopt.");
    }

    // Parse the existing toml both to validate it and to check for duplicates.
    let toml_str = fs::read_to_string(&dotfile_toml_path)?;
    let profile: Profile = toml::from_str(&toml_str)
        .map_err(|e| anyhow::anyhow!("Failed to parse {dotfile_toml_path:?}: {e}"))?;
    if profile.configs.iter().any(|c| c.path == rel_path_str) {
        bail!(
            "A config with path {rel_path_str:?} already exists in profile {:?}. Refusing to add a duplicate; edit dotfile.toml manually to add another platform.",
            profile.name
        );
    }

    // --- Build the new [[configs]] entry, preserving existing formatting/comments ---
    let mut doc = toml_str
        .parse::<toml_edit::Document>()
        .map_err(|e| anyhow::anyhow!("Failed to parse {dotfile_toml_path:?} for editing: {e}"))?;

    let mut install_location = toml_edit::InlineTable::new();
    install_location.insert(platform, opt.path.clone().into());

    let mut entry = toml_edit::Table::new();
    entry["name"] = toml_edit::value(opt.name.clone());
    entry["path"] = toml_edit::value(rel_path_str.clone());
    entry["install_location"] = toml_edit::value(install_location);

    let configs = doc["configs"].or_insert(toml_edit::Item::ArrayOfTables(
        toml_edit::ArrayOfTables::new(),
    ));
    let configs = configs
        .as_array_of_tables_mut()
        .ok_or_else(|| anyhow::anyhow!("`configs` in dotfile.toml is not an array of tables"))?;
    configs.push(entry);

    if opt.dryrun {
        log::info!("{} (dryrun) planned actions:", "Adopt".green());
        log::info!("  move {source_abs:?} -> {target_abs:?}");
        log::info!("  add [[configs]] entry {rel_path_str:?} for platform {platform:?}");
        log::info!("  symlink {source_abs:?} -> {target_abs:?}");
        return Ok(());
    }

    // --- Apply changes: move file, then update toml, then symlink ---
    log::info!("{} {source_abs:?} -> {target_abs:?}", "Moving".green());
    move_file(&source_abs, &target_abs)?;

    log::info!("{} {dotfile_toml_path:?}", "Updating".green());
    if let Err(e) = fs::write(&dotfile_toml_path, doc.to_string()) {
        // Roll back the move so we don't leave the original location empty.
        let _ = move_file(&target_abs, &source_abs);
        bail!("Failed to write updated dotfile.toml: {e}. Rolled back the file move.");
    }

    // --- Install the symlink for just this new config ---
    let parent_path = source_abs
        .parent()
        .ok_or_else(|| anyhow::anyhow!("Install path {source_abs:?} has no parent directory."))?
        .to_path_buf();
    let link = Link {
        install_path: source_abs.clone(),
        parent_path,
        target_path: target_abs.clone(),
    };
    create_symlink(&link)?;

    log::info!(
        "{} adopted {:?} into profile {:?}",
        "Successfully".green(),
        opt.name,
        profile.name
    );
    Ok(())
}

fn main() -> anyhow::Result<()> {
    log::set_logger(&Logger)
        .map(|()| log::set_max_level(log::LevelFilter::Info))
        .map_err(|e| anyhow::anyhow!(e))?;

    let opt = ProgArgs::parse();

    match opt {
        ProgArgs::Install(opt) => run_install(opt),
        ProgArgs::Adopt(opt) => run_adopt(opt),
    }
}

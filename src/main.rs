use anyhow::bail;
use colored::Colorize;
use logger::Logger;
use profile::Config;
use std::{
    fs,
    path::PathBuf,
    process::{Command, Stdio},
};
use structopt::StructOpt;

use crate::{profile::Profile, util::absolutize};

mod logger;
mod profile;
mod util;

#[derive(Debug, StructOpt)]
#[structopt(name = "Dotfiles", about = "Installs dotfiles using symlinks")]
struct Opt {
    /// Run all validations and install the files. Omit to run in dryrun mode
    #[structopt(short, long)]
    install: bool,

    /// Enable verbose mode
    #[structopt(short, long)]
    verbose: bool,

    /// Profile to install
    #[structopt(parse(from_os_str))]
    profile: PathBuf,
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

fn main() -> anyhow::Result<()> {
    log::set_logger(&Logger)
        .map(|()| log::set_max_level(log::LevelFilter::Info))
        .map_err(|e| anyhow::anyhow!(e))?;

    let opt = Opt::from_args();
    let dotfile_toml_path = opt.profile.join("dotfile.toml");

    log::info!("Parsing config {:?}", dotfile_toml_path);

    let dotfile_toml = fs::read_to_string(&dotfile_toml_path)?;
    let profile: Profile = toml::from_str(&dotfile_toml)?;

    if opt.verbose {
        log::info!("Parsed profile: {profile:#?}");
    }

    let links = validate(&opt.profile, &profile)?;

    if opt.install {
        install(&links)?;
    }

    Ok(())
}

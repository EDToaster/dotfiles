use colored::Colorize;
use logger::Logger;
use std::{error::Error, fmt, fs, path::PathBuf, process::Command};
use structopt::StructOpt;

use crate::{profile::Profile, util::absolutize};

mod logger;
mod profile;
mod util;

#[derive(Debug, StructOpt)]
#[structopt(name = "Dotfiles", about = "Installs dotfiles using symlinks")]
struct Opt {
    /// Enable dryrun mode, run all validations
    #[structopt(short, long)]
    install: bool,

    /// Enable verbose mode
    #[structopt(short, long)]
    verbose: bool,

    /// Profile to install
    #[structopt(parse(from_os_str))]
    profile: PathBuf,
}

#[derive(Debug)]
struct ValidationError;
impl Error for ValidationError {}

impl fmt::Display for ValidationError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Validation Error")
    }
}

struct Link {
    install_path: PathBuf,
    parent_path: PathBuf,
    target_path: PathBuf,
}
type Links = Vec<Link>;

/// For each config, we will validate that
/// 1. the target path exists, and
/// 2. the install location is specified in the profile
/// 3. the install location doesn't already have a file
///    (symlink is ok, but will show warning)
/// 4. the install parent path exists. If not, emit a warning.
/// Returns (number of warnings, number of errors)
fn validate(profile_base_path: &PathBuf, prof: &Profile) -> (usize, usize, Links) {
    let logger = Logger::new();

    let mut errs = 0usize;
    let mut warns = 0usize;
    let mut links: Links = vec![];
    for config in &prof.configs {
        logger.info(&format!("{} {config}", "Validating".green()));

        let logger = logger.scope();

        // Run pre-validation commands on the profile
        for cmd in &prof.validation_commands {
            logger.info(&format!("Spawning validation command {cmd:?}"));
            if cmd.is_empty() {
                errs += 1;
                logger.error("Validation command cannot be empty.");
                continue;
            }

            let proc = Command::new(&cmd[0]).args(&cmd[1..]).spawn();

            match proc {
                Ok(mut proc) => {
                    if let Ok(result) = proc.wait() {
                        if !result.success() {
                            errs += 1;
                            logger.error("Validation command failed");
                        }
                    } else {
                        errs += 1;
                        logger.error("Validation command failed");
                    }
                }
                Err(e) => {
                    errs += 1;
                    logger.error(&format!(
                        "Something went wrong with spawning the validation command: {e}"
                    ));
                }
            }
        }

        let mut target_path = profile_base_path.clone();
        target_path.push(&config.path);
        let target_path = absolutize(&target_path.display().to_string());

        // check target path exists
        if !target_path.exists() {
            errs += 1;
            logger.error(&format!("Target path {target_path:?} does not exist."));
        }

        // check the install location is specified in the profile
        let install_path = config.get_install_location();
        if let Some(install_path) = install_path {
            let parent_path = install_path.parent();

            // check install location doesn't already have a file
            if install_path.exists() {
                if install_path.is_symlink() {
                    warns += 1;
                    logger.warn("Install path exists as a symlink already.");
                } else {
                    errs += 1;
                    logger.error("Install path already exists as a file. Delete this file and rerun validations if it is safe to do so.");
                    continue;
                }
            }

            // check parent path already exists
            match parent_path {
                None => {
                    errs += 1;
                    logger.error("Install path does not have a parent directory.");
                    continue;
                }
                Some(parent_path) => {
                    if !parent_path.exists() {
                        warns += 1;
                        logger.warn("Install path's parent does not exist. It will be created.");
                    }
                    // passed validation, add to links
                    links.push(Link {
                        install_path: install_path.clone(),
                        parent_path: parent_path.into(),
                        target_path,
                    });
                }
            }
        } else {
            errs += 1;
            logger.error(&format!(
                "Install path is not specified for platform {}",
                std::env::consts::OS
            ));
            continue;
        }

        println!();
    }

    (warns, errs, links)
}

/// Create a symlink from inst to target.
/// Todo: https://doc.rust-lang.org/std/fs/fn.soft_link.html
/// Since this is deprecated, change to platform-dependent implmentation
/// when allowing for whole-directory symlinks.
#[allow(deprecated)]
fn symlink(link: &Link) -> Result<(), std::io::Error> {
    // Make sure parent path exists
    println!(
        "Creating parent directory (if needed) {:?}",
        link.parent_path
    );
    fs::create_dir_all(&link.parent_path)?;

    println!(
        "Removing existing install location (if needed) {:?}",
        link.install_path
    );
    match fs::remove_file(&link.install_path) {
        _ => {}
    } // ignore error

    println!(
        "Creating link {:?} -> {:?}",
        link.install_path, link.target_path
    );
    fs::soft_link(&link.target_path, &link.install_path)?;
    Ok(())
}

fn install(links: &Links) -> Result<(), std::io::Error> {
    for link in links {
        symlink(link)?;
    }
    Ok(())
}

fn main() -> Result<(), Box<dyn Error>> {
    let opt = Opt::from_args();
    let mut dotfile_toml_path = opt.profile.clone();
    dotfile_toml_path.push("dotfile.toml");

    println!("Parsing config {:?}", dotfile_toml_path);

    let dotfile_toml = fs::read_to_string(dotfile_toml_path)?;
    let profile: Profile = toml::from_str(&dotfile_toml)?;

    if opt.verbose {
        dbg!(&profile);
    }

    let (warns, errs, links) = validate(&opt.profile, &profile);
    println!("{warns} warnings found, {errs} errors found.");

    if errs > 0 {
        return Err(Box::new(ValidationError));
    }

    if opt.install {
        install(&links)?;
    }

    Ok(())
}

use colored::Colorize;
use std::{
    error::Error,
    fmt, fs,
    path::{Path, PathBuf},
};
use structopt::StructOpt;

use crate::profile::Profile;

mod profile;

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

/// For each config, we will validate that
/// 1. the target path exists, and
/// 2. the install location is specified in the profile
/// 3. the install location doesn't already have a file
///    (symlink is ok, but will show warning)
/// 4. the install parent path exists. If not, emit a warning.
/// Returns (number of warnings, number of errors)
fn validate(profile_base_path: &PathBuf, prof: &Profile) -> (usize, usize) {
    let mut errs = 0usize;
    let mut warns = 0usize;
    for config in &prof.configs {
        print!("{} ", "Validating".green());
        println!("{config}");

        let mut target_path = profile_base_path.clone();
        target_path.push(&config.path);

        // check target path exists
        if !target_path.exists() {
            errs += 1;
            println!(
                "\t{} target path {:?} does not exist.",
                "[ERROR]".red(),
                target_path
            );
        }

        // check the install location is specified in the profile
        let install_path = config.get_install_location();
        if let Some(install_path) = install_path {
            let parent_path = install_path.parent();

            // check install location doesn't already have a file
            if install_path.exists() {
                if install_path.is_symlink() {
                    warns += 1;
                    println!(
                        "\t{} install path exists as a symlink already.",
                        "[WARNING]".yellow()
                    );
                } else {
                    errs += 1;
                    println!(
                        "\t{} install path already exists as a file.",
                        "[ERROR]".red(),
                    );
                }
            }

            // check parent path already exists
            match parent_path {
                None => {
                    errs += 1;
                    println!(
                        "\t{} install path does not have a parent directory.",
                        "[ERROR]".red(),
                    );
                }
                Some(parent_path) => {
                    if !parent_path.exists() {
                        warns += 1;
                        println!(
                            "\t{} install path's parent does not exist. It will be created.",
                            "[WARNING]".yellow(),
                        );
                    }
                }
            }
        } else {
            errs += 1;
            println!(
                "\t{} install path is not specified for platform {}",
                "[ERROR]".red(),
                std::env::consts::OS
            );
        }

        println!();
    }

    (warns, errs)
}

fn install(prof: &Profile) {}

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

    let (warns, errs) = validate(&opt.profile, &profile);
    println!("{warns} warnings found, {errs} errors found.");

    if errs > 0 {
        return Err(Box::new(ValidationError));
    }

    if opt.install {
        install(&profile)
    }

    Ok(())
}

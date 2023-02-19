use std::{
    env,
    fmt::Display,
    path::{Path, PathBuf},
};

use serde::Deserialize;

#[derive(Debug, Deserialize)]
pub struct Profile {
    pub name: String,
    pub description: String,
    pub configs: Vec<Config>,
}

#[derive(Debug, Deserialize)]
pub struct Config {
    pub name: Option<String>,
    pub path: String,
    pub install_location: InstallLocation,
}

#[derive(Debug, Deserialize)]
#[serde(untagged)]
pub enum InstallLocation {
    Independent(String),
    Dependent {
        windows: Option<String>,
        macos: Option<String>,
        linux: Option<String>,
    },
}

impl Display for Config {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "{}: {:?} -> {}",
            self.get_display_name(),
            self.get_install_location(),
            self.path
        )
    }
}

fn absolutize(s: &str) -> PathBuf {
    // shell expand, if some of the environment variables don't exist, return original.
    let expanded = shellexpand::full(s)
        .map(|s| s.into_owned())
        .unwrap_or(s.to_owned());
    let mut abs_path = env::current_dir().unwrap();
    abs_path.push(expanded);
    abs_path
}

impl Config {
    pub fn get_display_name(&self) -> String {
        self.name.clone().unwrap_or(self.path.clone())
    }

    pub fn get_install_location(&self) -> Option<PathBuf> {
        match &self.install_location {
            InstallLocation::Independent(s) => Some(s.clone()),
            InstallLocation::Dependent {
                windows,
                macos,
                linux,
            } => match std::env::consts::OS {
                "windows" => windows.clone(),
                "macos" => macos.clone(),
                "linux" => linux.clone(),
                _ => None,
            },
        }
        .map(|p| absolutize(&p))
    }
}

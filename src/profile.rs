use std::{fmt::Display, path::PathBuf};

use serde::Deserialize;

use crate::util::absolutize;

#[derive(Debug, Deserialize)]
pub struct Profile {
    pub name: String,
    pub description: String,
    pub configs: Vec<Config>,
    #[serde(default)]
    pub validation_commands: Vec<Vec<String>>,
    #[serde(default)]
    pub optional_validation_commands: Vec<Vec<String>>,
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

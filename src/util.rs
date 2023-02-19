use std::{env, path::PathBuf};

pub fn absolutize(s: &str) -> PathBuf {
    // shell expand, if some of the environment variables don't exist, return original.
    let expanded = shellexpand::full(s)
        .map(|s| s.into_owned())
        .unwrap_or(s.to_owned());
    let mut abs_path = env::current_dir().unwrap();
    abs_path.push(expanded);
    abs_path
}

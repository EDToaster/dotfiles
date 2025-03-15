use colored::{ColoredString, Colorize};
use log::{Level, Log};

pub struct Logger;

fn prefix(level: Level) -> ColoredString {
    match level {
        Level::Error => "[ERROR]".red(),
        Level::Warn => "[WARN]".yellow(),
        Level::Info => "[INFO]".green(),
        Level::Debug => "[DEBUG]".dimmed(),
        Level::Trace => "[TRACE]".dimmed(),
    }
}

impl Log for Logger {
    fn enabled(&self, _metadata: &log::Metadata) -> bool {
        true
    }

    fn log(&self, record: &log::Record) {
        if self.enabled(record.metadata()) {
            println!("{} {}", prefix(record.level()), record.args())
        }
    }

    fn flush(&self) {
        todo!()
    }
}

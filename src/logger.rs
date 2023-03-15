use colored::{ColoredString, Colorize};

pub struct Logger {
    level: usize,
}

#[derive(Debug, Clone, Copy)]
pub enum Level {
    INFO,
    WARN,
    ERROR,
}

impl Level {
    pub fn prefix(&self) -> ColoredString {
        match &self {
            Level::INFO => "[INFO]".green(),
            Level::WARN => "[WARN]".yellow(),
            Level::ERROR => "[ERROR]".red(),
        }
    }
}

impl Logger {
    pub fn new() -> Self {
        Self { level: 0 }
    }

    pub fn scope(&self) -> Self {
        Self {
            level: self.level + 1,
        }
    }

    fn inner_print(&self, level: Option<Level>, content: &str) {
        for line in content.lines() {
            if let Some(level) = level {
                println!("{}{} {line}", "\t".repeat(self.level), level.prefix())
            } else {
                println!("{}{line}", "\t".repeat(self.level))
            }
        }
    }

    pub fn info(&self, content: &str) {
        self.inner_print(Some(Level::INFO), content);
    }

    pub fn warn(&self, content: &str) {
        self.inner_print(Some(Level::WARN), content);
    }

    pub fn error(&self, content: &str) {
        self.inner_print(Some(Level::ERROR), content);
    }
}

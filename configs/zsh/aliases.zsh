## Aliases

alias z=zellij
alias g=git
alias cat=bat
alias ls="eza -F --color=always"
alias dd="echo 'aliases: use \`caligula\` instead'"

eval "$(zoxide init zsh --cmd cd)"
# Check if the shell is interactive
if [[ -o interactive ]]; then
    eval "$(zoxide init zsh --cmd cd)"
else
    eval "$(zoxide init zsh)"
fi

## Aliases

alias z=zellij
alias g=git
alias cat=bat
alias ls="eza -F --color=always"
alias dd="echo 'aliases: use \`caligula\` instead'"

eval "$(zoxide init zsh --cmd cd)"

# cat() {
#     if command -v bat &> /dev/null; then
#         bat "$@"
#     else
#         command cat "$@"
#     fi
# }
# alias cat=cat


# ls() {
#     if command -v eza &> /dev/null; then
#         eza -F --color=always "$@"
#     else
#         command ls -F --color=auto "$@"
#     fi
# }
# alias ls=ls

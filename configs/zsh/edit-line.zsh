# Set up control-v to edit the current buffer
function edit-command-line-inplace() {
  if [[ $CONTEXT != start ]]; then
    if (( ! ${+widgets[edit-command-line]} )); then
      autoload -Uz edit-command-line
      zle -N edit-command-line
    fi
    zle edit-command-line
    return
  fi
  () {
    emulate -L zsh -o nomultibyte
    # Copy the file to a file with a .zsh suffix
    local file="$1.zsh"
    cp "$1" "$file"
    local editor=("${(@Q)${(z)${VISUAL:-${EDITOR:-vi}}}}") 
    "${(@)editor}" $file
    # Set buffer contents to the contents of the file
    BUFFER=$(<$file)
    # Set cursor to end of buffer
    CURSOR=$#BUFFER
  } =(<<<"$BUFFER")
}
  #"
# ^^ this is necessary since Helix doesn't recognize zsh's =() syntax,
# it borks the highlighting of everything after it.
zle -N edit-command-line-inplace
bindkey "^v" edit-command-line-inplace

_stat_zshrc_file() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    stat -f %m ~/.zshrc
  else
    stat -c %Y ~/.zshrc
  fi 
}

zshrc() {
  BEFORE=$(_stat_zshrc_file)
  $EDITOR ~/.zshrc
  AFTER=$(_stat_zshrc_file)
  if [[ "$BEFORE" -lt "$AFTER" ]]; then
    source ~/.zshrc
  else
    echo "Skipping source as file was not written"
  fi
}


zshrc() {
  BEFORE=$(stat -f %m ~/.zshrc)
  $EDITOR ~/.zshrc
  AFTER=$(stat -f %m ~/.zshrc)
  if [[ "$BEFORE" -lt "$AFTER" ]]; then
    source ~/.zshrc
  else
    echo "Skipping source as file was not written"
  fi
}


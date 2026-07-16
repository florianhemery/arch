# Honor Hyprland — zsh
export EDITOR=vim
export LANG=fr_FR.UTF-8

autoload -Uz compinit && compinit
setopt autocd histignoreall sharehistory appendhistory

HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000

eval "$(starship init zsh)"

alias ls='eza --icons'
alias ll='eza -la --icons'
alias cat='bat'

# .bashrc


# Source global definitions
if [ -f /etc/bashrc ]; then
    . /etc/bashrc
fi


# User specific environment
if ! [[ "$PATH" =~ "$HOME/.local/bin:$HOME/bin:" ]]; then
    PATH="$HOME/.local/bin:$HOME/bin:$PATH"
fi
export PATH


# Uncomment the following line if you don't like systemctl's auto-paging feature:
# export SYSTEMD_PAGER=

# User specific aliases and functions
if [ -d ~/.bashrc.d ]; then
    for rc in ~/.bashrc.d/*; do
        if [ -f "$rc" ]; then
            . "$rc"
        fi
    done
fi
unset rc


# aliases
alias la='ls -lha --color=auto'
alias o='xdg-open'
alias top='top -U $USER'
alias htop='htop -u'

alias myip='curl ifconfig.me'

alias gs='git status'
alias ga='git add .'
alias gc='git commit -m'
alias gp='git push'
alias gl='git pull'
alias gh='git checkout'
alias gm='git merge'
alias gr='git reset'

alias py='python'
alias pyenv='python -m venv .venv'
alias uvr='uv run'
alias pmm='python manage.py makemigrations'
alias pmg='python manage.py migrate'
alias pmu='python manage.py createsuperuser'
alias pmr='python manage.py runserver'
alias pmc='python manage.py collectstatic'
alias pmf='python manage.py flush'
alias pmt='python manage.py tailwind'
alias pipf='pip freeze > requirements.txt'
alias pipi='pip install -r requirements.txt'
alias pipc='pip freeze | xargs pip uninstall -y'
alias ali='alembic init alembic'
alias alr='alembic revision --autogenerate -m'
alias alu='alembic upgrade head'


# functions
mkcd () {
	mkdir -p "$1"
	cd "$1"
}

extract () {
    if [ -f "$1" ] ; then
        case "$1" in
            *.tar.bz2)   tar xjf "$1"    ;;
            *.tar.gz)    tar xzf "$1"    ;;
            *.bz2)       bunzip2 "$1"    ;;
            *.rar)       unrar x "$1"    ;;
            *.gz)        gunzip "$1"     ;;
            *.tar)       tar xf "$1"     ;;
            *.tbz2)      tar xjf "$1"    ;;
            *.tgz)       tar xzf "$1"    ;;
            *.zip)       unzip "$1"      ;;
            *.Z)         uncompress "$1" ;;
            *.7z)        7z x "$1"       ;;
            *)           echo "'$1' cannot be extracted via extract()" ;;
        esac
    else
        echo "'$1' is not a valid file"
    fi
}

cleanall () {
	echo "🧹 Cleaning temporary files..."
	rm -rf /tmp/* ~/.cache/thumbnails/ ~/.cache/pip/ ~/.cache/npm/ ~/.cache/fastfetch/ ~/.cache/flatpak/
	sudo dnf clean all -y
	sudo journalctl --vacuum-time=7d
	echo "✅ Done. Clearing terminal..."
	clear
}

gclone() {
    local default_user="fathiabdelmalek"

    if [ $# -lt 1 ]; then
        echo "Usage: gclone <repository> [<username>] [<target-dir>]"
        return 1
    fi

    local repo=$1
    local user=${2:-$default_user}
    local target=${3:-${repo%.git}}

    git clone "git@github.com:${user}/${repo}.git" "$target"
}


passgen () {
	if [ -z "$1" ]; then
		echo "Usage: passgen <context-word>"
        	return 1
	fi
	local context="$1"
	year=$(date +%Y)
	passphera passwords generate -c "$context" -t "fathi: $context generated on $year"
}

function auto_venv () {
    if [ -f ".venv/bin/activate" ]; then
        source .venv/bin/activate
    fi
}

cd () {
    builtin cd "$@" || return
    auto_venv
}
. "$HOME/.cargo/env"

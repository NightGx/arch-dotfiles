# ==============================================================================
# ENVIRONNEMENT & VARIABLES GLOBALES
# ==============================================================================
set -gx MANGOHUD 1
set -gx CLAUDE_CODE_MAX_OUTPUT_TOKENS 999999
set -gx GTK_IM_MODULE ibus

# Amazon Q (chargement si l'intégration Fish existe)
if test -f "$HOME/.local/share/amazon-q/shell/amazon-q.fish"
    source "$HOME/.local/share/amazon-q/shell/amazon-q.fish"
end

# ==============================================================================
# SESSION INTERACTIVE
# ==============================================================================
if status is-interactive

    # --- Prompt (Starship gère nativement le statut Git) ---
    starship init fish | source

    # --- Aliases ---
    alias ls='ls -a --color=auto'
    alias ll='ls -alF'
    alias la='ls -A'
    alias l='ls -CF'
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
    alias glog='git log --all --pretty="format:%d %Cgreen%h%Creset %an - %s" --graph'
    
    # Redémarrage du terminal (adapté pour Kitty sur Arch)
    alias restart='kitty --detach; exit'

    # ==========================================================================
    # PROFILS GIT
    # ==========================================================================
    function git-perso --description "Switch sur mon compte GitHub (Night)"
        set -gx GIT_AUTHOR_NAME "NightGx"
        set -gx GIT_AUTHOR_EMAIL "nightgx8@gmail.com"
        set -gx GIT_COMMITTER_NAME "NightGx"
        set -gx GIT_COMMITTER_EMAIL "nightgx8@gmail.com"
        echo "Profil Git actif : (GitHub) NightGx"
    end

    function git-pro --description "Switch sur mon compte GitHub (TLableigne)"
        set -gx GIT_AUTHOR_NAME "TLableigne"
        set -gx GIT_AUTHOR_EMAIL "thom1.lableigne@gmail.com"
        set -gx GIT_COMMITTER_NAME "TLableigne"
        set -gx GIT_COMMITTER_EMAIL "thom1.lableigne@gmail.com"
        echo "Profil Git actif : (GitHub) Thomas"
    end

    function git-etu --description "Switch sur mon compte GitLab (Thomas L) étudiant"
        set -gx GIT_AUTHOR_NAME "Thomas L"
        set -gx GIT_AUTHOR_EMAIL "thomas.lableigne@etu.u-bordeaux.fr"
        set -gx GIT_COMMITTER_NAME "Thomas L"
        set -gx GIT_COMMITTER_EMAIL "thomas.lableigne@etu.u-bordeaux.fr"
        echo "Profil Git actif : (GitLab) Thomas L"
    end

    # ==========================================================================
    # OUTILS & FONCTIONS PERSO
    # ==========================================================================
    function list --description "Affiche la liste de mes fonctions perso et leur description"
        # On récupère les noms des fonctions définies dans config.fish
        for fn in (grep -E '^\s*function ' ~/.config/fish/config.fish | awk '{print $2}')
            # functions --details -v renvoie la description en 5ème ligne
            set -l desc (functions --details -v $fn | sed -n '5p')
            test "$desc" = "n/a"; and set desc "Aucune description"

            printf "\033[1;36mName :\033[0m %s\n\033[1;33mDescription :\033[0m %s\n\n" "$fn" "$desc"
        end
    end

    function findall --description "Cherche un fichier sur tout le disque (ignore les erreurs)"
        if test (count $argv) -eq 0
            echo "Usage: findall <nom_fichier>"
            return 1
        end
        sudo find / -name $argv[1] 2>/dev/null
    end

    function power --description "Affiche le statut et la batterie de la G502 X et du WH-1000XM5"
        echo "G502 X"
        if upower -e | grep -q 'hidpp_battery'
            upower -i $(upower -e | grep 'hidpp_battery') | grep -E "model|percentage"
        else
            echo "  offline"
        end

        echo "WH-1000XM5"
        if bluetoothctl info 58:18:62:55:8F:5F | grep -q "Connected: yes"
            upower -i $(upower -e | grep -E "headset|headphones|bluez" | head -n 1) | grep -E "model|percentage"
        else
            echo "  offline"
        end
    end

    function info --description "Lance btop et nvtop en split vertical dans tmux"
        if not command -v tmux >/dev/null 2>&1
            echo "tmux n'est pas installé. Lancez : sudo pacman -S tmux"
            return 1
        end

        tmux new-session 'btop' \; split-window -v 'nvtop' \; set -g mouse on
    end

    function create-dual-repo --description "Crée et configure un double dépôt GitHub (NightGx + TLableigne)"
        set -l NAME $argv[1]
        test -z "$NAME"; and set NAME (basename (pwd))
        set -l VISIBILITY $argv[2]
        test -z "$VISIBILITY"; and set VISIBILITY "--public"

        echo "==> Initialisation Git locale..."
        git init -b main 2>/dev/null; or git init

        echo "==> Création du dépôt sur le compte NightGx..."
        gh auth switch -u NightGx
        gh repo create "NightGx/$NAME" $VISIBILITY

        echo "==> Création du dépôt sur le compte TLableigne..."
        gh auth switch -u TLableigne
        gh repo create "TLableigne/$NAME" $VISIBILITY

        echo "==> Configuration des remotes SSH..."
        git remote remove night 2>/dev/null; or true
        git remote remove thomas 2>/dev/null; or true
        git remote remove all 2>/dev/null; or true

        git remote add night "git@github-night:NightGx/$NAME.git"
        git remote add thomas "git@github-thomas:TLableigne/$NAME.git"

        git remote add all "git@github-night:NightGx/$NAME.git"
        git remote set-url --add --push all "git@github-night:NightGx/$NAME.git"
        git remote set-url --add --push all "git@github-thomas:TLableigne/$NAME.git"

        gh auth switch -u NightGx

        echo "==> Terminé ! Remotes configurés :"
        git remote -v
    end

    function ssh-server
        ssh -t server 'exec bash --rcfile <(echo "source ~/.bashrc; PS1=\"\[\e[38;5;220m\]\u@\h\[\e[0m\]:\[\e[38;5;39m\]\w\[\e[0m\]\\$ \"")'
    end
end

# ==============================================================================
# AUTOSTART HYPRLAND (TTY1)
# ==============================================================================
if status is-login
    if test -z "$WAYLAND_DISPLAY" -a "$XDG_VTNR" = 1
        exec start-hyprland
    end
end

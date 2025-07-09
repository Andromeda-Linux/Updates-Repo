#!/usr/bin/env bash

# ====================== KOLORY ======================
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

LOG_FILE="/tmp/update-andromeda-linux.log"

# ==================== FUNKCJE =======================

show_banner() {
    clear
    echo -e "${MAGENTA}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
    echo -e "┃${CYAN}                     ANDROMEDA LINUX UPDATE                               ${MAGENTA}┃"
    echo -e "┃━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┃"
    echo -e "┃                                                                     ┃"
    echo -e "┃    System update utility - July 2025                               ┃"
    echo -e "┃                                                                     ┃"
    echo -e "┃    Author: Michał                                                   ┃"
    echo -e "┃    Purpose: Comprehensive update for Andromeda Linux system        ┃"
    echo -e "┃                                                                     ┃"
    echo -e "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo
}

spinner() {
    local pid=$1
    local delay=0.1
    local bar_length=12
    local pos=0
    local spinner_str="===>"

    while kill -0 "$pid" 2>/dev/null; do
        # Tworzymy pasek z przesuwającym się "===>"
        local bar=""
        for ((i=0; i<bar_length; i++)); do
            bar+=" "
        done

        # Obliczamy pozycję przesuwania
        local offset=$((pos % (bar_length + ${#spinner_str})))

        # Tworzymy pasek z przesunięciem str
        if (( offset < bar_length )); then
            # Wstawiamy spinner_str do paska w pozycji offset
            bar="${bar:0:offset}${spinner_str}${bar:offset+${#spinner_str}}"
        else
            # Poza zasięgiem, pasek pusty
            bar="${bar}"
        fi

        printf "\r${YELLOW}Aktualizacja w toku... [%s]${NC}" "$bar"
        sleep $delay
        ((pos++))
    done
    printf "\r${GREEN}Aktualizacja zakończona.                      ${NC}\n"
}

check_internet() {
    echo -e "${CYAN}Sprawdzanie połączenia z internetem...${NC}"
    if ! ping -c 1 archlinux.org &> /dev/null; then
        echo -e "${RED}Brak połączenia z internetem. Anulowano.${NC}"
        exit 1
    fi
    echo -e "${GREEN}Połączenie OK${NC}\n"
}

show_versions() {
    echo -e "${CYAN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
    echo -e "┃        INFORMACJE SYSTEMU     ┃"
    echo -e "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    printf "${WHITE}%-15s ${GREEN}%s${NC}\n" "Kernel:" "$(uname -r)"
    printf "${WHITE}%-15s ${GREEN}%s${NC}\n\n" "Distro:" "$(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d \")"
}

perform_update() {
    echo -e "\n${CYAN}Rozpoczynam aktualizację, zapisywanie logów do: ${LOG_FILE}${NC}"
    echo "" > "$LOG_FILE"

    echo -e "${CYAN}[1/5] Aktualizacja pakietów systemowych (zypper)${NC}" | tee -a "$LOG_FILE"
    sudo zypper refresh >> "$LOG_FILE" 2>&1
    sudo zypper update -y >> "$LOG_FILE" 2>&1

    echo -e "${CYAN}[2/5] Aktualizacja Flatpak${NC}" | tee -a "$LOG_FILE"
    if command -v flatpak &> /dev/null; then
        flatpak update -y >> "$LOG_FILE" 2>&1
    else
        echo -e "${YELLOW}Flatpak nie jest zainstalowany.${NC}" | tee -a "$LOG_FILE"
    fi

    echo -e "${CYAN}[3/5] Aktualizacja Snap${NC}" | tee -a "$LOG_FILE"
    if command -v snap &> /dev/null; then
        sudo snap refresh >> "$LOG_FILE" 2>&1
    else
        echo -e "${YELLOW}Snap nie jest zainstalowany.${NC}" | tee -a "$LOG_FILE"
    fi

    echo -e "${CYAN}[4/5] Aktualizacja firmware (fwupd)${NC}" | tee -a "$LOG_FILE"
    if command -v fwupdmgr &> /dev/null; then
        sudo fwupdmgr refresh >> "$LOG_FILE" 2>&1
        sudo fwupdmgr get-updates >> "$LOG_FILE" 2>&1
        sudo fwupdmgr update -y >> "$LOG_FILE" 2>&1
    else
        echo -e "${YELLOW}fwupd nie jest zainstalowany.${NC}" | tee -a "$LOG_FILE"
    fi

    echo -e "${CYAN}[5/5] Uruchamianie skryptu aktualizacji Andromeda${NC}" | tee -a "$LOG_FILE"
    if [ -f /usr/share/Andromeda-Linux/Scripts/Andromeda/update-andromeda.sh ]; then
        sudo bash /usr/share/Andromeda-Linux/Scripts/Andromeda/update-andromeda.sh >> "$LOG_FILE" 2>&1
    else
        echo -e "${YELLOW}Skrypt Andromeda update nie został znaleziony.${NC}" | tee -a "$LOG_FILE"
    fi
}

post_update_menu() {
    echo -e "${CYAN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
    echo -e "┃     AKTUALIZACJA ZAKOŃCZONA    ┃"
    echo -e "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"

    echo -e "${MAGENTA}
[ r ] Restart systemu
[ s ] Shutdown
[ l ] Logout
[ t ] Spróbuj ponownie
[ e ] Wyjście
${NC}"

    read -n1 -p "Wybierz opcję: " choice
    echo ""

    case "$choice" in
        r|R)
            echo -e "${YELLOW}Restartowanie systemu...${NC}"
            sudo reboot
            ;;
        s|S)
            echo -e "${YELLOW}Wyłączanie systemu...${NC}"
            sudo poweroff
            ;;
        l|L)
            echo -e "${YELLOW}Wylogowywanie...${NC}"
            pkill -KILL -u "$USER"
            ;;
        t|T)
            echo -e "${YELLOW}Ponowne uruchamianie skryptu...${NC}"
            exec "$0"
            ;;
        e|E)
            echo -e "${GREEN}Zakończono.${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Nieznana opcja. Zakończono.${NC}"
            exit 1
            ;;
    esac
}

# ====================== START ========================

show_banner
check_internet
show_versions

perform_update &

pid=$!
spinner $pid

post_update_menu

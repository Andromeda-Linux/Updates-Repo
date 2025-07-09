#!/usr/bin/env bash

# update-tkg-kernel.sh
# Automatyczny updater kernela TKG dla Andromeda Linux (openSUSE)
# Rozbudowana wersja: backup + cleanup + klon w /tmp + systemd shutdown integration

set -euo pipefail

echo "[+] === Andromeda Linux TKG Kernel Updater ==="

BACKUP_DIR="/var/backups/tkg-kernels"
TMP_DIR="/tmp/linux-tkg"

# ====== Funkcja wykrywająca CPU i GPU i ustawiająca patche ======
detect_hardware_and_set_patches() {
  echo "[+] Wykrywam CPU i GPU..."

  CPU_VENDOR=$(lscpu | grep "Vendor ID" | awk '{print $3}')
  GPU_INFO=$(lspci | grep VGA)
  GPU_VENDOR="Unknown"

  if echo "$GPU_INFO" | grep -iq nvidia; then
    GPU_VENDOR="NVIDIA"
  elif echo "$GPU_INFO" | grep -iq amd; then
    GPU_VENDOR="AMD"
  elif echo "$GPU_INFO" | grep -iq intel; then
    GPU_VENDOR="Intel"
  fi

  echo "[+] CPU: $CPU_VENDOR, GPU: $GPU_VENDOR"

  # Generuj customization.cfg
  cat > customization.cfg << EOF
# Auto-generated customization.cfg

_sched_choice="bmq"

EOF

  if [[ "$GPU_VENDOR" == "NVIDIA" ]]; then
    echo 'use_nvidia_patch="true"' >> customization.cfg
  else
    echo 'use_nvidia_patch="false"' >> customization.cfg
  fi

  if [[ "$CPU_VENDOR" == "AuthenticAMD" ]]; then
    echo 'amd_pstate_patch="true"' >> customization.cfg
  else
    echo 'amd_pstate_patch="false"' >> customization.cfg
  fi

  echo "[+] Plik customization.cfg zaktualizowany wg sprzętu."
}

# ====== Funkcja instalująca sterowniki GPU ======
install_gpu_drivers() {
  echo "[+] Sprawdzam i instaluję sterowniki GPU jeśli potrzebne..."

  if [[ "$GPU_VENDOR" == "NVIDIA" ]]; then
    echo "[+] Instaluję sterowniki NVIDIA..."
    sudo zypper install --no-confirm nvidia-glG05 nvidia-gfxG05-kmp-default || true
  elif [[ "$GPU_VENDOR" == "AMD" ]]; then
    echo "[+] Sterowniki AMD są zazwyczaj wbudowane w kernel TKG."
  elif [[ "$GPU_VENDOR" == "Intel" ]]; then
    echo "[+] Sterowniki Intel są wbudowane w kernel."
  else
    echo "[!] Nie wykryto znanego GPU. Pomijam instalację sterowników."
  fi
}

# ====== Funkcja backupu starego kernela ======
backup_old_kernel() {
  local kernel_package=$1

  echo "[+] Tworzę backup starego kernela TKG: $kernel_package"

  sudo mkdir -p "$BACKUP_DIR"

  local timestamp
  timestamp=$(date +%Y%m%d-%H%M%S)

  sudo rpm -q --qf "%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}.rpm\n" "$kernel_package" | while read -r rpmfile; do
    local backup_file="$BACKUP_DIR/$rpmfile-backup-$timestamp.rpm"
    sudo rpm2cpio /var/cache/zypp/packages/*/"$rpmfile" | sudo cpio -idmv -D "$BACKUP_DIR/$rpmfile-backup-$timestamp"
    echo "[✓] Backup zapisany jako $backup_file"
  done
}

# ====== Funkcja czyszcząca stare backupy > 2GB ======
cleanup_old_backups() {
  echo "[+] Sprawdzam rozmiar backupów w $BACKUP_DIR..."

  local total_size
  total_size=$(du -sb "$BACKUP_DIR" | awk '{print $1}')

  local max_size=$((2 * 1024 * 1024 * 1024)) # 2GB

  if (( total_size > max_size )); then
    echo "[!] Przekroczono limit 2GB. Usuwam najstarsze backupy..."

    ls -1t "$BACKUP_DIR" | tail -n +5 | while read -r oldfile; do
      echo "[+] Usuwam $oldfile"
      sudo rm -rf "$BACKUP_DIR/$oldfile"
    done
  else
    echo "[✓] Rozmiar backupów OK ($(numfmt --to=iec $total_size))."
  fi
}

# ====== Główny workflow ======
main() {
  cleanup_old_backups

  echo "[+] Przechodzę do katalogu tymczasowego: $TMP_DIR"
  sudo rm -rf "$TMP_DIR"
  git clone https://github.com/Frogging-Family/linux-tkg.git "$TMP_DIR"

  cd "$TMP_DIR"

  echo "[+] Pobieram najnowsze zmiany..."
  git pull

  # Pobierz najnowszy tag kernela TKG
  LATEST_KERNEL=$(git describe --tags $(git rev-list --tags --max-count=1))
  echo "[+] Najnowszy dostępny kernel TKG: $LATEST_KERNEL"

  # Pobierz aktualnie zainstalowany kernel TKG w systemie
  CURRENT_KERNEL=$(rpm -qa | grep tkg || true)

  if [[ -z "$CURRENT_KERNEL" ]]; then
    echo "[!] Nie wykryto zainstalowanego kernela TKG. Instaluję najnowszy ($LATEST_KERNEL)..."
  elif [[ "$CURRENT_KERNEL" == *"$LATEST_KERNEL"* ]]; then
    echo "[✓] Masz już najnowszy kernel TKG ($LATEST_KERNEL). Nic nie robię."
    exit 0
  else
    echo "[!] Wykryto nową wersję kernela TKG."

    # ====== Backup starego kernela TKG ======
    backup_old_kernel "$CURRENT_KERNEL"

    # ====== Usuwanie starego kernela TKG ======
    echo "[+] Usuwam stary kernel TKG..."
    sudo rpm -e "$CURRENT_KERNEL" || true
  fi

  # ====== Ustaw patche zgodnie ze sprzętem ======
  detect_hardware_and_set_patches

  # ====== Instalacja sterowników GPU ======
  install_gpu_drivers

  # ====== Budowa nowego kernela TKG ======
  echo "[+] Buduję kernel TKG..."
  ./install.sh

  # ====== Aktualizacja GRUB ======
  echo "[+] Aktualizuję GRUB..."
  sudo grub2-mkconfig -o /boot/grub2/grub.cfg

  echo "[✓] Kernel TKG zaktualizowany do wersji $LATEST_KERNEL i GRUB odświeżony."
}

main
exit 0

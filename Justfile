# Constants

repo_image_name := "ublue-custom"
repo_name := "alistairporter"
username := "alistairporter"
IMAGE_REGISTRY := "ghcr.io/" + repo_name
FQ_IMAGE_NAME := IMAGE_REGISTRY + "/" + repo_image_name
images := '(
    [aurora]="aurora"
    [aurora-nvidia]="aurora-nvidia-open"
    [bazzite]="bazzite-gnome-nvidia-open"
    [bazzite-deck]="bazzite-deck-gnome"
    [bluefin]="bluefin"
    [bluefin-nvidia]="bluefin-nvidia-open"
    [cosmic]="cosmic"
    [cosmic-nvidia]="cosmic-nvidia-open"
    [ucore]="stable-zfs"
    [ucore-nvidia]="stable-nvidia-zfs"
)'

# Build Containers

isobuilder := "ghcr.io/jasonn3/build-container-installer@" + RENOVATE_ISO_DIGEST
rechunker := "ghcr.io/hhd-dev/rechunk@" + RENOVATE_RECHUNKER_DIGEST
qemu := "ghcr.io/qemus/qemu@" + RENOVATE_QEMU_DIGEST
cosign-installer := "cgr.dev/chainguard/cosign@" + RENOVATE_COSIGN_DIGEST
syft-installer := "docker.io/anchore/syft@" + RENOVATE_SYFT_DIGEST

[private]
default:
    @{{ just }} --list

# Check Just Syntax
[group('Just')]
@check:
    {{ just }} --unstable --fmt --check -f Justfile

# Fix Just Syntax
[group('Just')]
@fix:
    {{ just }} --unstable --fmt -f Justfile

# Cleanup
[group('Utility')]
clean:
    #!/usr/bin/bash
    set -euox pipefail
    touch {{ repo_image_name }}_ || true
    {{ SUDOIF }} find {{ repo_image_name }}_* -type d -exec chmod 0755 {} \;
    {{ SUDOIF }} find {{ repo_image_name }}_* -type f -exec chmod 0644 {} \;
    find {{ repo_image_name }}_* -maxdepth 0 -exec rm -rf {} \;
    rm -f output*.env changelog*.md version.txt previous.manifest.json
    rm -f ./*.sbom.*

# Build Image
[group('Image')]
build image="bluefin":
    #!/usr/bin/bash
    echo "::group:: Container Build Prep"
    set ${SET_X:+-x} -eou pipefail
    declare -A images={{ images }}
    check=${images[{{ image }}]-}
    if [[ -z "$check" ]]; then
        exit 1
    fi
    BUILD_ARGS=()
    mkdir -p {{ BUILD_DIR }}
    TMPDIR="$(mktemp -d -p {{ BUILD_DIR }})"
    trap 'rm -rf $TMPDIR' EXIT SIGINT
    case "{{ image }}" in
    "aurora"*|"bluefin"*)
        BASE_IMAGE="${check}"
        TAG_VERSION=stable-daily
        {{ just }} verify-container "${BASE_IMAGE}":"${TAG_VERSION}"
        skopeo inspect docker://ghcr.io/ublue-os/"${BASE_IMAGE}":"${TAG_VERSION}" > "$TMPDIR/inspect-{{ image }}.json"
        fedora_version="$(jq -r '.Labels["ostree.linux"]' < "$TMPDIR/inspect-{{ image }}.json" | grep -oP 'fc\K[0-9]+')"
        ;;
    "bazzite"*)
        BASE_IMAGE=${check}
        TAG_VERSION=stable
        {{ just }} verify-container "${BASE_IMAGE}":"${TAG_VERSION}"
        skopeo inspect docker://ghcr.io/ublue-os/"${BASE_IMAGE}":"${TAG_VERSION}" > "$TMPDIR/inspect-{{ image }}.json"
        fedora_version="$(jq -r '.Labels["ostree.linux"]' < "$TMPDIR/inspect-{{ image }}.json" | grep -oP 'fc\K[0-9]+')"
        ;;
    "cosmic"*)
        {{ just }} verify-container bluefin:stable-daily
        fedora_version="$(skopeo inspect docker://ghcr.io/ublue-os/bluefin:stable-daily | jq -r '.Labels["ostree.linux"]' | grep -oP 'fc\K[0-9]+')"
        {{ just }} verify-container akmods:coreos-stable-"${fedora_version}"
        BASE_IMAGE=base-main
        TAG_VERSION="${fedora_version}"
        {{ just }} verify-container "${BASE_IMAGE}":"${TAG_VERSION}"
        skopeo inspect docker://ghcr.io/ublue-os/akmods:coreos-stable-"${fedora_version}" > "$TMPDIR/inspect-{{ image }}.json"
        ;;
    "ucore"*)
        BASE_IMAGE=ucore
        TAG_VERSION="$check"
        {{ just }} verify-container "$BASE_IMAGE":"$TAG_VERSION"
        skopeo inspect docker://ghcr.io/ublue-os/"$BASE_IMAGE":"$TAG_VERSION" > "$TMPDIR/inspect-{{ image }}.json"
        fedora_version="$(jq -r '.Labels["ostree.linux"]' < "$TMPDIR/inspect-{{ image }}.json" | grep -oP 'fc\K[0-9]+')"
        # fedora_version="$(skopeo inspect docker://ghcr.io/ublue-os/$BASE_IMAGE:"$TAG_VERSION" | jq -r '.Labels["ostree.linux"]' | grep -oP 'fc\K[0-9]+')"
        # {{ just }} verify-container akmods:coreos-stable-"${fedora_version}"
        # skopeo inspect docker://ghcr.io/ublue-os/akmods:coreos-stable-"${fedora_version}" > "$TMPDIR/inspect-{{ image }}.json"
        ;;
    esac

    VERSION="{{ image }}-${fedora_version}.$(date +%Y%m%d)"
    skopeo list-tags docker://{{ FQ_IMAGE_NAME }} > "$TMPDIR"/repotags.json
    if [[ $(jq "any(.Tags[]; contains(\"$VERSION\"))" < "$TMPDIR"/repotags.json) == "true" ]]; then
        POINT="1"
        while jq -e "any(.Tags[]; contains(\"$VERSION.$POINT\"))" >/dev/null < "$TMPDIR"/repotags.json
        do
            (( POINT++ ))
        done
    fi
    if [[ -n "${POINT:-}" ]]; then
        VERSION="${VERSION}.$POINT"
    fi
    # Pull The image
    {{ PODMAN }} pull "ghcr.io/ublue-os/$BASE_IMAGE:$TAG_VERSION"

    #Build Args
    BUILD_ARGS+=("--file" "Containerfile")
    BUILD_ARGS+=("--label" "org.opencontainers.image.source=https://github.com/{{ repo_name }}/{{ repo_image_name }}")
    BUILD_ARGS+=("--label" "org.opencontainers.image.title={{ repo_image_name }}")
    BUILD_ARGS+=("--label" "org.opencontainers.image.version=$VERSION")
    BUILD_ARGS+=("--label" "ostree.linux=$(jq -r '.Labels["ostree.linux"]' < "$TMPDIR"/inspect-{{ image }}.json)")
    BUILD_ARGS+=("--label" "org.opencontainers.image.description={{ repo_image_name }} is my OCI image built from ublue projects. It mainly extends them for my uses.")
    BUILD_ARGS+=("--build-arg" "IMAGE={{ image }}")
    BUILD_ARGS+=("--build-arg" "BASE_IMAGE=$BASE_IMAGE")
    BUILD_ARGS+=("--build-arg" "TAG_VERSION=$TAG_VERSION")
    BUILD_ARGS+=("--build-arg" "SET_X=${SET_X:-}")
    BUILD_ARGS+=("--build-arg" "VERSION=$VERSION")
    BUILD_ARGS+=("--tag" "localhost/{{ repo_image_name }}:{{ image }}")
    BUILD_ARGS+=("--tag" "localhost/{{ repo_image_name }}:$VERSION")
    if [[ {{ PODMAN }} =~ docker  && "${TERM}" == "dumb" ]]; then
        BUILD_ARGS+=("--progress" "plain")
    fi
    echo "::endgroup::"

    {{ PODMAN }} build "${BUILD_ARGS[@]}" .

    if [[ "${UID}" -gt "0" ]]; then
        {{ just }} rechunk {{ image }}
    else
        {{ PODMAN }} rmi -f ghcr.io/ublue-os/"${BASE_IMAGE}":"${TAG_VERSION}"
    fi

# Rechunk Image
[group('Image')]
rechunk image="bluefin":
    #!/usr/bin/bash
    echo "::group:: Rechunk Build Prep"
    set ${SET_X:+-x} -eou pipefail

    ID=$({{ PODMAN }} images --filter reference=localhost/{{ repo_image_name }}:{{ image }} --format "'{{ '{{.ID}}' }}'")

    if [[ -z "$ID" ]]; then
        {{ just }} build {{ image }}
    fi

    if [[ "${UID}" -gt "0" && ! {{ PODMAN }} =~ docker ]]; then
        mkdir -p "{{ BUILD_DIR }}"
        COPYTMP="$(mktemp -dp "{{ BUILD_DIR }}")"
        {{ SUDOIF }} TMPDIR="${COPYTMP}" {{ PODMAN }} image scp "${UID}"@localhost::localhost/{{ repo_image_name }}:{{ image }} root@localhost::localhost/{{ repo_image_name }}:{{ image }}
        rm -rf "${COPYTMP}"
    fi

    CREF=$({{ SUDOIF }} {{ PODMAN }} create localhost/{{ repo_image_name }}:{{ image }} bash)
    if [[ {{ PODMAN }} =~ podman ]]; then
        MOUNT=$({{ SUDOIF }} {{ PODMAN }} mount "$CREF")
    else
        MOUNTFS="{{ BUILD_DIR }}/{{ image }}_rootfs"
        {{ SUDOIF }} rm -rf "$MOUNTFS"
        mkdir -p "$MOUNTFS"
        {{ PODMAN }} export "$CREF" | tar -x -C "$MOUNTFS"
        MOUNT="{{ GIT_ROOT }}/$MOUNTFS"
    fi
    OUT_NAME="{{ repo_image_name }}_{{ image }}.tar"
    VERSION="$({{ SUDOIF }} {{ PODMAN }} inspect "$CREF" | jq -r '.[]["Config"]["Labels"]["org.opencontainers.image.version"]')"
    LABELS="
    org.opencontainers.image.source=https://github.com/{{ repo_name }}/{{ repo_image_name }}
    org.opencontainers.image.title={{ repo_image_name }}:{{ image }}
    org.opencontainers.image.revision=$(git rev-parse HEAD)
    ostree.linux=$({{ SUDOIF }} {{ PODMAN }} inspect "$CREF" | jq -r '.[].["Config"]["Labels"]["ostree.linux"]')
    org.opencontainers.image.description={{ repo_image_name }} is my OCI image built from ublue projects. It mainly extends them for my uses.
    "
    echo "::endgroup::"

    echo "::group:: Rechunk Prune"
    {{ SUDOIF }} {{ PODMAN }} run --rm \
        --security-opt label=disable \
        --volume "$MOUNT":/var/tree \
        --env TREE=/var/tree \
        --user 0:0 \
        {{ rechunker }} \
        /sources/rechunk/1_prune.sh
    echo "::endgroup::"

    echo "::group:: Create Tree"
    {{ SUDOIF }} {{ PODMAN }} run --rm \
        --security-opt label=disable \
        --volume "$MOUNT":/var/tree \
        --volume "cache_ostree:/var/ostree" \
        --env TREE=/var/tree \
        --env REPO=/var/ostree/repo \
        --env RESET_TIMESTAMP=1 \
        --user 0:0 \
        {{ rechunker }} \
        /sources/rechunk/2_create.sh
    if [[ "{{ PODMAN }}" =~ podman ]]; then
        {{ SUDOIF }} {{ PODMAN }} unmount "$CREF"
    else
        {{ SUDOIF }} rm -rf "$MOUNTFS"
    fi
    {{ SUDOIF }} {{ PODMAN }} rm "$CREF"
    if [[ "${UID}" -gt "0" && "{{ PODMAN }}" =~ podman ]]; then
        {{ SUDOIF }} {{ PODMAN }} rmi -f localhost/{{ repo_image_name }}:{{ image }}
    fi
    {{ PODMAN }} rmi -f localhost/{{ repo_image_name }}:{{ image }}
    echo "::endgroup::"

    echo "::group:: Rechunk"
    {{ SUDOIF }} {{ PODMAN }} run --rm \
        --security-opt label=disable \
        --volume "{{ GIT_ROOT }}:/workspace" \
        --volume "{{ GIT_ROOT }}:/var/git" \
        --volume cache_ostree:/var/ostree \
        --env REPO=/var/ostree/repo \
        --env PREV_REF={{ FQ_IMAGE_NAME }}:{{ image }} \
        --env LABELS="$LABELS" \
        --env OUT_NAME="$OUT_NAME" \
        --env VERSION="$VERSION" \
        --env VERSION_FN=/workspace/version.txt \
        --env OUT_REF="oci-archive:$OUT_NAME" \
        --env GIT_DIR="/var/git" \
        --user 0:0 \
        {{ rechunker }} \
        /sources/rechunk/3_chunk.sh
    echo "::endgroup::"

    echo "::group:: Cleanup"
    if [[ "${UID}" -gt "0" ]]; then
        {{ SUDOIF }} chown -R "${UID}":"${GROUPS[0]}" "$PWD"
        {{ just }} load-image {{ image }}
    elif [[ "${UID}" == "0" && -n "${SUDO_USER:-}" ]]; then
        {{ SUDOIF }} chown -R "${SUDO_UID}":"${SUDO_GID}" "/run/user/${SUDO_UID}/just"
        {{ SUDOIF }} chown -R "${SUDO_UID}":"${SUDO_GID}" "$PWD"
    fi

    {{ SUDOIF }} {{ PODMAN }} volume rm cache_ostree
    echo "::endgroup::"

# Load Image into Podman and Tag
[group('CI')]
load-image image="bluefin":
    #!/usr/bin/bash
    set ${SET_X:+-x} -eou pipefail
    if [[ {{ PODMAN }} =~ podman ]]; then
        IMAGE=$(podman pull oci-archive:{{ repo_image_name }}_{{ image }}.tar)
        podman tag "${IMAGE}" localhost/{{ repo_image_name }}:{{ image }}
    else
        skopeo copy oci-archive:{{ repo_image_name }}_{{ image }}.tar docker-daemon:localhost/{{ repo_image_name }}:{{ image }}
    fi
    VERSION=$(skopeo inspect oci-archive:{{ repo_image_name }}_{{ image }}.tar | jq -r '.Labels["org.opencontainers.image.version"]')
    {{ PODMAN }} tag localhost/{{ repo_image_name }}:{{ image }} localhost/{{ repo_image_name }}:"${VERSION}"
    {{ PODMAN }} images

# Get Tags
[group('CI')]
get-tags image="bluefin":
    #!/usr/bin/bash
    set ${SET_X:+-x} -eou pipefail
    VERSION=$({{ PODMAN }} inspect {{ repo_image_name }}:{{ image }} | jq -r '.[]["Config"]["Labels"]["org.opencontainers.image.version"]')
    echo "{{ image }} $VERSION"

# Build ISO
[group('ISO')]
build-iso image="bluefin" ghcr="0" clean="0":
    #!/usr/bin/bash
    set ${SET_X:+-x} -eou pipefail
    # Validate
    declare -A images={{ images }}
    check=${images[{{ image }}]-}
    if [[ -z "$check" ]]; then
        exit 1
    fi

    # Verify ISO Build Container
    {{ just }} verify-container "build-container-installer@{{ RENOVATE_ISO_DIGEST }}" "ghcr.io/jasonn3" "https://raw.githubusercontent.com/JasonN3/build-container-installer/refs/heads/main/cosign.pub"

    mkdir -p {{ BUILD_DIR }}/{lorax_templates,flatpak-refs-{{ image }},output}
    echo 'append etc/anaconda/profile.d/fedora-kinoite.conf "\\n[User Interface]\\nhidden_spokes =\\n    PasswordSpoke"' \
         > {{ BUILD_DIR }}/lorax_templates/remove_root_password_prompt.tmpl

    # Build from GHCR or localhost
    IMAGE_REPO={{ IMAGE_REGISTRY }}
    TEMPLATES=("/github/workspace/{{ BUILD_DIR }}/lorax_templates/remove_root_password_prompt.tmpl")
    if [[ "{{ ghcr }}" -gt "0" ]]; then
        IMAGE_FULL={{ FQ_IMAGE_NAME }}:{{ image }}
        if [[ "{{ ghcr }}" == "1" ]]; then
            # Verify Container for ISO
            {{ just }} verify-container "{{ repo_image_name }}:{{ image }}" "${IMAGE_REPO}" "https://raw.githubusercontent.com/{{ repo_name }}/{{ repo_image_name }}/refs/heads/main/cosign.pub"
            {{ PODMAN }} pull "${IMAGE_FULL}"
        elif [[ "{{ ghcr }}" == "2" ]]; then
            {{ just }} load-image {{ image }}
            {{ PODMAN }} tag localhost/{{ repo_image_name }}:{{ image }} "$IMAGE_FULL"
        fi
    else
        IMAGE_FULL=localhost/{{ repo_image_name }}:{{ image }}
        ID=$({{ PODMAN }} images --filter reference=${IMAGE_FULL} --format "'{{ '{{.ID}}' }}'")
        if [[ -z "$ID" ]]; then
            {{ just }} build {{ image }}
        fi
    fi

    # Check if ISO already exists. Remove it.
    if [[ -f "{{ BUILD_DIR }}/output/{{ image }}.iso" || -f "{{ BUILD_DIR }}/output/{{ image }}.iso-CHECKSUM" ]]; then
        rm -f {{ BUILD_DIR }}/output/{{ image }}.iso*
    fi

    # Load image into rootful podman
    if [[ "${UID}" -gt "0" && ! {{ PODMAN }} =~ docker ]]; then
        mkdir -p {{ BUILD_DIR }}
        COPYTMP="$(mktemp -dp {{ BUILD_DIR }})"
        {{ SUDOIF }} TMPDIR="${COPYTMP}" {{ PODMAN }} image scp "${UID}"@localhost::"${IMAGE_FULL}" root@localhost::"${IMAGE_FULL}"
        rm -rf "${COPYTMP}"
    fi

    # Generate Flatpak List
    TEMP_FLATPAK_INSTALL_DIR="$(mktemp -dp {{ BUILD_DIR }})"
    trap 'rm -rf "$TEMP_FLATPAK_INSTALL_DIR"' EXIT SIGINT
    FLATPAK_REFS_DIR="{{ BUILD_DIR }}/flatpak-refs-{{ image }}"
    mkdir -p "${FLATPAK_REFS_DIR}"
    FLATPAK_REFS_DIR_ABS="{{ GIT_ROOT }}/${FLATPAK_REFS_DIR}"
    case "{{ image }}" in
    *"aurora"*)
        FLATPAK_LIST_URL="https://raw.githubusercontent.com/ublue-os/aurora/refs/heads/main/aurora_flatpaks/flatpaks"
    ;;
    *"bazzite"*)
        FLATPAK_LIST_URL="https://raw.githubusercontent.com/ublue-os/bazzite/refs/heads/main/installer/gnome_flatpaks/flatpaks"
    ;;
    *"bluefin"*|*"cosmic"*)
        FLATPAK_LIST_URL="https://raw.githubusercontent.com/ublue-os/bluefin/refs/heads/main/bluefin_flatpaks/flatpaks"
    ;;
    esac
    curl -Lo "${FLATPAK_REFS_DIR}"/flatpaks.txt "${FLATPAK_LIST_URL}"
    ADDITIONAL_FLATPAKS=(
        app/com.discordapp.Discord/x86_64/stable
        app/com.spotify.Client/x86_64/stable
        app/org.gimp.GIMP/x86_64/stable
        app/org.libreoffice.LibreOffice/x86_64/stable
        app/org.prismlauncher.PrismLauncher/x86_64/stable
    )
    if [[ "{{ image }}" =~ bazzite ]]; then
        ADDITIONAL_FLATPAKS+=(app/org.gnome.World.PikaBackup/x86_64/stable)
    elif [[ "{{ image }}" =~ aurora|bluefin|cosmic ]]; then
        ADDITIONAL_FLATPAKS+=(app/it.mijorus.gearlever/x86_64/stable)
    fi
    FLATPAK_REFS=()
    while IFS= read -r line; do
    FLATPAK_REFS+=("$line")
    done < "${FLATPAK_REFS_DIR}/flatpaks.txt"
    FLATPAK_REFS+=("${ADDITIONAL_FLATPAKS[@]}")
    echo "Flatpak refs: ${FLATPAK_REFS[*]}"
    # Generate installation script
    tee "${TEMP_FLATPAK_INSTALL_DIR}/install-flatpaks.sh"<<EOF
    mkdir -p /flatpak/flatpak /flatpak/triggers
    mkdir /var/tmp
    mkdir /var/roothome
    chmod -R 1777 /var/tmp
    flatpak config --system --set languages "*"
    flatpak remote-add --system flathub https://flathub.org/repo/flathub.flatpakrepo
    flatpak install --system -y flathub ${FLATPAK_REFS[@]}
    ostree refs --repo=\${FLATPAK_SYSTEM_DIR}/repo | grep '^deploy/' | grep -v 'org\.freedesktop\.Platform\.openh264' | sed 's/^deploy\///g' > /output/flatpaks-with-deps
    EOF
    # Create Flatpak List
    [[ ! -f "$FLATPAK_REFS_DIR/flatpaks-with-deps" ]] && \
    {{ SUDOIF }} {{ PODMAN }} run --rm --privileged \
    --entrypoint /bin/bash \
    -e FLATPAK_SYSTEM_DIR=/flatpak/flatpak \
    -e FLATPAK_TRIGGERS_DIR=/flatpak/triggers \
    -v "${FLATPAK_REFS_DIR_ABS}":/output \
    -v "{{ GIT_ROOT }}/${TEMP_FLATPAK_INSTALL_DIR}":/temp_flatpak_install_dir \
    "${IMAGE_FULL}" /temp_flatpak_install_dir/install-flatpaks.sh

    VERSION="$({{ SUDOIF }} {{ PODMAN }} inspect ${IMAGE_FULL} | jq -r '.[]["Config"]["Labels"]["ostree.linux"]' | grep -oP 'fc\K[0-9]+')"
    if [[ "{{ ghcr }}" -ge "1" && "{{ clean }}" == "1" ]]; then
        {{ SUDOIF }} {{ PODMAN }} rmi ${IMAGE_FULL}
    fi
    # list Flatpaks
    cat "${FLATPAK_REFS_DIR}"/flatpaks-with-deps
    #ISO Container Args
    iso_build_args=()
    if [[ "{{ ghcr }}" == "0" && "{{ PODMAN }}" =~ podman ]]; then
        iso_build_args+=(--volume "/var/lib/containers/storage:/var/lib/containers/storage")
    elif [[ "{{ ghcr }}" == "0" && "{{ PODMAN }}" =~ docker ]]; then
        iso_build_args+=(--volume "/var/run/docker.sock:/var/run/docker.sock")
    fi
    iso_build_args+=(--volume "{{ GIT_ROOT }}:/github/workspace/")
    iso_build_args+=({{ isobuilder }})
    iso_build_args+=(ADDITIONAL_TEMPLATES="${TEMPLATES[@]}")
    iso_build_args+=(ARCH="x86_64")
    iso_build_args+=(ENROLLMENT_PASSWORD="universalblue")
    iso_build_args+=(FLATPAK_REMOTE_REFS_DIR="/github/workspace/${FLATPAK_REFS_DIR}")
    iso_build_args+=(IMAGE_NAME="{{ repo_image_name }}")
    iso_build_args+=(IMAGE_REPO="${IMAGE_REPO}")
    iso_build_args+=(IMAGE_SIGNED="true")
    if [[ "{{ ghcr }}" == "0" && "{{ PODMAN }}" =~ podman ]]; then
        iso_build_args+=(IMAGE_SRC="containers-storage:${IMAGE_FULL}")
    elif [[ "{{ ghcr }}" == "0" && "{{ PODMAN }}" =~ docker ]]; then
        iso_build_args+=(IMAGE_SRC="docker-daemon:${IMAGE_FULL}")
    elif [[ "{{ ghcr }}" == "2" ]]; then
        iso_build_args+=(IMAGE_SRC="oci-archive:/github/workspace/{{ repo_image_name }}_{{ image }}.tar")
    fi
    iso_build_args+=(IMAGE_TAG="{{ image }}")
    iso_build_args+=(ISO_NAME="/github/workspace/{{ BUILD_DIR }}/output/{{ image }}.iso")
    iso_build_args+=(SECURE_BOOT_KEY_URL="https://github.com/ublue-os/akmods/raw/main/certs/public_key.der")
    iso_build_args+=(VARIANT="Kinoite")
    iso_build_args+=(VERSION="$VERSION")
    iso_build_args+=(WEB_UI="false")
    # Build ISO
    {{ SUDOIF }} {{ PODMAN }} run --rm --privileged --security-opt label=disable "${iso_build_args[@]}"
    if [[ "{{ PODMAN }}" =~ docker ]]; then
        {{ SUDOIF }} chown -R "${UID}":"${GROUPS[0]}" "$PWD"
    elif [[ "${UID}" -gt "0" ]]; then
        {{ SUDOIF }} chown -R "${UID}":"${GROUPS[0]}" "$PWD"
        {{ SUDOIF }} {{ PODMAN }} rmi "${IMAGE_FULL}"
    elif [[ "${UID}" == "0" && -n "${SUDO_USER:-}" ]]; then
        {{ SUDOIF }} chown -R "${SUDO_UID}":"${SUDO_GID}" "$PWD"
    fi

# Run ISO
[group('ISO')]
run-iso image="bluefin":
    #!/usr/bin/bash
    set ${SET_X:+-x} -eou pipefail
    if [[ ! -f "{{ BUILD_DIR }}/output/{{ image }}.iso" ]]; then
        {{ just }} build-iso {{ image }}
    fi
    port=8006;
    while grep -q "${port}" <<< "$(ss -tunalp)"; do
        port=$(( port + 1 ))
    done
    echo "Using Port: ${port}"
    echo "Connect to http://localhost:${port}"
    (sleep 30 && (xdg-open http://localhost:"${port}" || true))&
    run_args=()
    run_args+=(--rm --privileged)
    run_args+=(--publish "127.0.0.1:${port}:8006")
    run_args+=(--env "CPU_CORES=4")
    run_args+=(--env "RAM_SIZE=8G")
    run_args+=(--env "DISK_SIZE=64G")
    run_args+=(--env "BOOT_MODE=windows_secure")
    run_args+=(--env "TPM=Y")
    run_args+=(--env "GPU=Y")
    run_args+=(--device=/dev/kvm)
    run_args+=(--volume "{{ GIT_ROOT }}/{{ BUILD_DIR }}/output/{{ image }}.iso":"/boot.iso":z)
    run_args+=({{ qemu }})
    {{ PODMAN }} run "${run_args[@]}"

# Test Changelogs
[group('Changelogs')]
changelogs target="Desktop" urlmd="" handwritten="":
    #!/usr/bin/bash
    set ${SET_X:+-x} -eou pipefail
    python3 changelogs.py {{ target }} ./output-{{ target }}.env ./changelog-{{ target }}.md --workdir . --handwritten "{{ handwritten }}" --urlmd "{{ urlmd }}"

# Verify Container with Cosign
[group('Utility')]
verify-container container="" registry="ghcr.io/ublue-os" key="": install-cosign
    #!/usr/bin/bash
    set ${SET_X:+-x} -eou pipefail

    # Public Key for Container Verification
    key={{ key }}
    if [[ -z "${key:-}" && "{{ registry }}" == "ghcr.io/ublue-os" ]]; then
        key="https://raw.githubusercontent.com/ublue-os/main/main/cosign.pub"
    fi

    # Verify Container using cosign public key
    if ! cosign verify --key "${key}" "{{ registry }}"/"{{ container }}" >/dev/null; then
        echo "NOTICE: Verification failed. Please ensure your public key is correct."
        exit 1
    fi

# Secureboot Check
[group('CI')]
secureboot image="bluefin":
    #!/usr/bin/bash
    set ${SET_X:+-x} -eou pipefail
    # Get the vmlinuz to check
    kernel_release=$({{ PODMAN }} inspect "{{ image }}" | jq -r '.[].Config.Labels["ostree.linux"]')
    TMP=$({{ PODMAN }} create "{{ image }}" bash)
    TMPDIR="$(mktemp -d -p .)"
    trap 'rm -rf $TMPDIR' EXIT
    {{ PODMAN }} cp "$TMP":/usr/lib/modules/"${kernel_release}"/vmlinuz "$TMPDIR/vmlinuz"
    {{ PODMAN }} rm "$TMP"

    # Get the Public Certificates
    curl --retry 3 -Lo "$TMPDIR"/kernel-sign.der https://github.com/ublue-os/kernel-cache/raw/main/certs/public_key.der
    curl --retry 3 -Lo "$TMPDIR"/akmods.der https://github.com/ublue-os/kernel-cache/raw/main/certs/public_key_2.der
    openssl x509 -in "$TMPDIR"/kernel-sign.der -out "$TMPDIR"/kernel-sign.crt
    openssl x509 -in "$TMPDIR"/akmods.der -out "$TMPDIR"/akmods.crt

    # Make sure we have sbverify
    CMD="$(command -v sbverify)" || true
    if [[ -z "${CMD:-}" ]]; then
        temp_name="sbverify-${RANDOM}"
        {{ PODMAN }} run -dt \
            --entrypoint /bin/sh \
            --workdir {{ GIT_ROOT }} \
            --volume "{{ GIT_ROOT }}/$TMPDIR/:{{ GIT_ROOT }}/$TMPDIR/:z" \
            --name ${temp_name} \
            alpine:edge
        {{ PODMAN }} exec "${temp_name}" apk add sbsigntool
        CMD="{{ PODMAN }} exec ${temp_name} /usr/bin/sbverify"
    fi

    # Confirm that Signatures Are Good
    $CMD --list "$TMPDIR/vmlinuz"
    returncode=0
    if ! $CMD --cert "$TMPDIR/kernel-sign.crt" "$TMPDIR/vmlinuz" || ! $CMD --cert "$TMPDIR/akmods.crt" "$TMPDIR/vmlinuz"; then
        echo "Secureboot Signature Failed...."
        returncode=1
    fi
    if [[ -n "${temp_name:-}" ]]; then
        {{ PODMAN }} rm -f "${temp_name}"
    fi
    exit "$returncode"

# Merge Changelogs
[group('Changelogs')]
merge-changelog:
    #!/usr/bin/bash
    set ${SET_X:+-x} -eou pipefail
    rm -f changelog.md
    mapfile -t changelogs < <(find . -type f -name changelog\*.md | sort -r)
    cat "${changelogs[@]}" > changelog.md
    last_tag=$(git tag --list {{ repo_image_name }}-\* | sort -V | tail -1)
    date_extract="$(echo "${last_tag:-}" | grep -oP '{{ repo_image_name }}-\K[0-9]+')"
    date_version="$(echo "${last_tag:-}" | grep -oP '\.\K[0-9]+$' || true)"
    if [[ "${date_extract:-}" == "$(date +%Y%m%d)" ]]; then
        tag="{{ repo_image_name }}-${date_extract:-}.$(( ${date_version:-} + 1 ))"
    else
        tag="{{ repo_image_name }}-$(date +%Y%m%d)"
    fi
    cat << EOF
    {
        "title": "$tag (#$(git rev-parse --short HEAD))",
        "tag": "$tag"
    }
    EOF

# Lint Files
[group('Utility')]
@lint:
    # shell
    /usr/bin/find . -iname "*.sh" -type f -exec shellcheck "{}" ';'
    # yaml
    yamllint -s {{ justfile_dir() }}
    # just
    {{ just }} check
    # just recipes
    {{ just }} lint-recipes

# Format Files
[group('Utility')]
@format:
    # shell
    /usr/bin/find . -iname "*.sh" -type f -exec shfmt --write "{}" ';'
    # yaml
    yamlfmt {{ justfile_dir() }}
    # just
    {{ just }} fix

# Linter Helper
[group('Utility')]
_lint-recipe linter recipe *args:
    #!/usr/bin/bash
    set -eou pipefail
    mkdir -p {{ BUILD_DIR }}
    TMPDIR="$(mktemp -d -p {{ BUILD_DIR }})"
    trap 'rm -rf "$TMPDIR"' EXIT SIGINT
    {{ just }} -n {{ recipe }} {{ args }} 2>&1 | tee "$TMPDIR"/{{ recipe }} >/dev/null
    linter=({{ linter }})
    echo "Linting {{ style('warning') }}{{ recipe }}{{ NORMAL }} with {{ style('command') }}${linter[0]}{{ NORMAL }}"
    {{ linter }} "$TMPDIR"/{{ recipe }} && rm "$TMPDIR"/{{ recipe }} || rm "$TMPDIR"/{{ recipe }}

# Linter Helper
[group('Utility')]
lint-recipes:
    #!/usr/bin/bash
    recipes=(
        build
        build-iso
        changelogs
        cosign-sign
        gen-sbom
        get-tags
        load-image
        push-to-registry
        rechunk
        run-iso
        sbom-sign
        secureboot
        verify-container
    )
    for recipe in "${recipes[@]}"; do
        {{ just }} _lint-recipe "shellcheck -s bash -e SC2050,SC2194" "$recipe" bluefin
    done
    recipes=(
        clean
        install-cosign
        lint-recipes
        merge-changelog
    )
    for recipe in "${recipes[@]}"; do
        {{ just }} _lint-recipe "shellcheck -s bash -e SC2050,SC2194" "$recipe"
    done

# Get Cosign if Needed
[group('CI')]
install-cosign:
    #!/usr/bin/bash

    # Get Cosign from Chainguard
    if [[ ! $(command -v cosign) ]]; then
        COSIGN_CONTAINER_ID=$({{ SUDOIF }} {{ PODMAN }} create {{ cosign-installer }} bash)
        {{ SUDOIF }} {{ PODMAN }} cp "${COSIGN_CONTAINER_ID}":/usr/bin/cosign /usr/local/bin/cosign
        {{ SUDOIF }} {{ PODMAN }} rm -f "${COSIGN_CONTAINER_ID}"
    fi
    # Verify Cosign Image Signatures if needed
    if [[ -n "${COSIGN_CONTAINER_ID:-}" ]]; then
        if ! cosign verify --certificate-oidc-issuer=https://token.actions.githubusercontent.com --certificate-identity=https://github.com/chainguard-images/images/.github/workflows/release.yaml@refs/heads/main cgr.dev/chainguard/cosign >/dev/null; then
            echo "NOTICE: Failed to verify cosign image signatures."
            exit 1
        fi
        {{ SUDOIF }} {{ PODMAN }} rmi -f cgr.dev/chainguard/cosign:latest
    fi

# Login to GHCR
[group('CI')]
@login-to-ghcr $user $token:
    echo "$token" | podman login ghcr.io -u "$user" --password-stdin
    echo "$token" | docker login ghcr.io -u "$user" --password-stdin

# Push Images to Registry
[group('CI')]
push-to-registry image $dryrun="true" $destination="":
    #!/usr/bin/bash
    set ${SET_X:+-x} -eou pipefail

    if [[ -z "$destination" ]]; then
        destination="docker://{{ IMAGE_REGISTRY }}"
    fi

    # Get Tag List
    declare -a TAGS=("$(skopeo inspect oci-archive:{{ repo_image_name }}_{{ image }}.tar | jq -r '.Labels["org.opencontainers.image.version"]')")
    TAGS+=("{{ image }}")

    # Push
    if [[ "{{ dryrun }}" == "false" ]]; then
        for tag in "${TAGS[@]}"; do
            skopeo copy "oci-archive:{{ repo_image_name }}_{{ image }}.tar" "$destination/{{ repo_image_name }}:$tag"
        done
    fi

    # Pass Digest
    digest="$(skopeo inspect "oci-archive:{{ repo_image_name }}_{{ image }}.tar" --format '{{{{ .Digest }}')"
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        echo "digest=$digest" >> "$GITHUB_OUTPUT"
    fi
    echo "$digest"

# Sign Images with Cosign
[group('CI')]
cosign-sign digest $destination="": install-cosign
    #!/usr/bin/bash
    set ${SET_X:+-x} -eou pipefail
    if [[ -z "$destination" ]]; then
        destination="{{ IMAGE_REGISTRY }}"
    fi
    cosign sign -y --key env://COSIGN_PRIVATE_KEY "$destination/{{ repo_image_name }}@{{ digest }}"

# Generate SBOM
[group('CI')]
gen-sbom $input $output="":
    #!/usr/bin/bash
    set ${SET_X:+-x} -eou pipefail

    # Get SYFT if needed
    SYFT_ID=""
    if [[ ! $(command -v syft) ]]; then
        SYFT_ID="$({{ SUDOIF }} {{ PODMAN }} create {{ syft-installer }})"
        {{ SUDOIF }} {{ PODMAN }} cp "$SYFT_ID":/syft /usr/local/bin/syft
        {{ SUDOIF }} {{ PODMAN }} rm -f "$SYFT_ID" > /dev/null
        {{ SUDOIF }} {{ PODMAN }} rmi -f docker.io/anchore/syft:latest
        trap '{{ SUDOIF }} rm -f /usr/local/bin/syft; exit 1' SIGINT
    fi

    # Enable Podman Socket if needed
    if [[ "$EUID" -eq "0" && "{{ PODMAN }}" =~ podman ]] && ! systemctl is-active -q podman.socket; then
        systemctl start podman.socket
        started_podman="true"
    elif ! systemctl is-active -q --user podman.socket && [[ "{{ PODMAN }}" =~ podman ]]; then
        systemctl start --user podman.socket
        started_podman="true"
    fi

    # Make SBOM
    if [[ -z "$output" ]]; then
        OUTPUT_PATH="$(mktemp -d)/sbom.json"
    else
        OUTPUT_PATH="$output"
    fi
    env SYFT_PARALLELISM="$(nproc)" syft scan "{{ input }}" -o spdx-json="$OUTPUT_PATH"

    # Cleanup
    if [[ "$EUID" -eq "0" && "${started_podman:-}" == "true" ]]; then
        systemctl stop podman.socket
    elif [[ "${started_podman:-}" == "true" ]]; then
        systemctl stop --user podman.socket
    fi
    # if [[ -n "$SYFT_ID" ]]; then
    #     {{ SUDOIF }} rm -f /usr/local/bin/syft
    # fi

    # Output Path
    echo "$OUTPUT_PATH"

# Add SBOM attestation
[group('CI')]
sbom-sign image $sbom="": install-cosign
    #!/usr/bin/bash
    set ${SET_X:+-x} -eou pipefail

    # set SBOM
    if [[ ! -f "$sbom" ]]; then
        sbom="$({{ just }} gen-sbom {{ image }})"
    fi

    # Sign-blob Args
    SBOM_SIGN_ARGS=(
       "--key" "env://COSIGN_PRIVATE_KEY"
       "--output-signature" "$sbom.sig"
       "$sbom"
    )

    # Sign SBOM
    cosign sign-blob -y "${SBOM_SIGN_ARGS[@]}"

    # Verify-blob Args
    SBOM_VERIFY_ARGS=(
        "--key" "cosign.pub"
        "--signature" "$sbom.sig"
        "$sbom"
    )

    # Verify Signature
    cosign verify-blob "${SBOM_VERIFY_ARGS[@]}"

# Just Executable

export just := just_executable()

# SUDO

export SUDO_DISPLAY := if `if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then echo true; fi` == "true" { "true" } else { "false" }
export SUDOIF := if `id -u` == "0" { "" } else if SUDO_DISPLAY == "true" { "sudo --askpass" } else { "sudo" }

# Quiet By Default

export SET_X := if `id -u` == "0" { "1" } else { env('SET_X', '') }

# Podman By Default

export PODMAN := if path_exists("/usr/bin/podman") == "true" { env("PODMAN", "/usr/bin/podman") } else if path_exists("/usr/bin/docker") == "true" { env("PODMAN", "docker") } else { env("PODMAN", "exit 1 ; ") }

# Workspace Folder

GIT_ROOT := env("LOCAL_WORKSPACE_DIR", justfile_dir())

# Build Dir

BUILD_DIR := repo_image_name + "_build"

# Build Containers
# renovate: datasource=docker packageName=ghcr.io/jasonn3/build-container-installer

RENOVATE_ISO_VERSION := "v1.2.4"
RENOVATE_ISO_DIGEST := "sha256:99156bea504884d10b2c9fe85f7b171deea18a2619269d7a7e6643707e681ad7"

# renovate: datasource=docker packageName=ghcr.io/hhd-dev/rechunk

RENOVATE_RECHUNKER_VERSION := "v1.2.1"
RENOVATE_RECHUNKER_DIGEST := "sha256:3db87ea9548cc15d5f168e3d58ede27b943bbadc30afee4e39b7cd6d422338b5"

# renovate: datasource=docker packageName=anchore/syft

RENOVATE_SYFT_VERSION := "v1.22.0"
RENOVATE_SYFT_DIGEST := "sha256:b7b38b51897feb0a8118bbfe8e43a1eb94aaef31f8d0e4663354e42834a12126"

# renovate: datasource=docker packageName=chainguard/cosign

RENOVATE_COSIGN_VERSION := "latest"
RENOVATE_COSIGN_DIGEST := "sha256:86a197ca63dc0396806632092370749b4060fb745168b7b9e1d196baa43331d3"

# renovate: datasource=docker packageName=ghcr.io/qemus/qemu

RENOVATE_QEMU_VERSION := "7.10"
RENOVATE_QEMU_DIGEST := "sha256:1765084b0a1d13a8361ff11568f0bda8519b06f1d4e4616b0cc900af5d186be9"

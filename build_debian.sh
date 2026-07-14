oh_my_posh_VERSION=$1
BUILD_VERSION=$2
ARCH=${3:-amd64}  # Default to amd64 if no architecture specified

if [ -z "$oh_my_posh_VERSION" ] || [ -z "$BUILD_VERSION" ]; then
    echo "Usage: $0 <oh_my_posh_version> <build_version> [architecture]"
    echo "Example: $0 29.28.0 1 arm64"
    echo "Example: $0 29.28.0 1 all    # Build for all architectures"
    echo "Supported architectures: amd64, arm64, armhf, all"
    exit 1
fi

# Function to map Debian architecture to oh-my-posh release asset name
get_omp_release() {
    local arch=$1
    case "$arch" in
        "amd64")
            echo "posh-linux-amd64"
            ;;
        "arm64")
            echo "posh-linux-arm64"
            ;;
        "armhf")
            echo "posh-linux-arm"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Download the themes once — shared by every architecture and distribution
download_themes() {
    if [ -d themes ]; then
        return 0
    fi
    if ! wget -q "https://github.com/JanDeDobbeleer/oh-my-posh/releases/download/v${oh_my_posh_VERSION}/themes.zip"; then
        echo "❌ Failed to download themes.zip"
        return 1
    fi
    mkdir -p themes
    if ! unzip -q -o themes.zip -d themes; then
        echo "❌ Failed to extract themes.zip"
        return 1
    fi
    rm -f themes.zip
    echo "✅ Themes downloaded ($(ls themes | wc -l) files)"
}

# Function to build for a specific architecture
build_architecture() {
    local build_arch=$1
    local omp_release

    omp_release=$(get_omp_release "$build_arch")
    if [ -z "$omp_release" ]; then
        echo "❌ Unsupported architecture: $build_arch"
        echo "Supported architectures: amd64, arm64, armhf"
        return 1
    fi

    echo "Building for architecture: $build_arch using $omp_release"

    # Clean up any previous builds for this architecture
    rm -f "$omp_release" || true

    # Download oh-my-posh binary for this architecture
    if ! wget -q "https://github.com/JanDeDobbeleer/oh-my-posh/releases/download/v${oh_my_posh_VERSION}/${omp_release}"; then
        echo "❌ Failed to download oh-my-posh binary for $build_arch"
        return 1
    fi

    # Build packages for all Debian distributions
    declare -a arr=("bookworm" "trixie" "forky" "sid")

    for dist in "${arr[@]}"; do
        FULL_VERSION="$oh_my_posh_VERSION-${BUILD_VERSION}~${dist}_${build_arch}"
        echo "  Building $FULL_VERSION"

        if ! docker build . -t "oh-my-posh-$dist-$build_arch" \
            --build-arg DEBIAN_DIST="$dist" \
            --build-arg oh_my_posh_VERSION="$oh_my_posh_VERSION" \
            --build-arg BUILD_VERSION="$BUILD_VERSION" \
            --build-arg FULL_VERSION="$FULL_VERSION" \
            --build-arg ARCH="$build_arch" \
            --build-arg OMP_RELEASE="$omp_release"; then
            echo "❌ Failed to build Docker image for $dist on $build_arch"
            return 1
        fi

        id="$(docker create "oh-my-posh-$dist-$build_arch")"
        if ! docker cp "$id:/oh-my-posh_$FULL_VERSION.deb" - > "./oh-my-posh_$FULL_VERSION.deb"; then
            echo "❌ Failed to extract .deb package for $dist on $build_arch"
            return 1
        fi

        if ! tar -xf "./oh-my-posh_$FULL_VERSION.deb"; then
            echo "❌ Failed to extract .deb contents for $dist on $build_arch"
            return 1
        fi
    done

    # Clean up downloaded binary
    rm -f "$omp_release" || true

    echo "✅ Successfully built for $build_arch"
    return 0
}

# Main build logic
if ! download_themes; then
    exit 1
fi

if [ "$ARCH" = "all" ]; then
    echo "🚀 Building oh-my-posh $oh_my_posh_VERSION-$BUILD_VERSION for all supported architectures..."
    echo ""

    ARCHITECTURES=("amd64" "arm64" "armhf")

    for build_arch in "${ARCHITECTURES[@]}"; do
        echo "==========================================="
        echo "Building for architecture: $build_arch"
        echo "==========================================="

        if ! build_architecture "$build_arch"; then
            echo "❌ Failed to build for $build_arch"
            exit 1
        fi

        echo ""
    done

    echo "🎉 All architectures built successfully!"
    echo "Generated packages:"
    ls -la oh-my-posh_*.deb
else
    # Build for single architecture
    if ! build_architecture "$ARCH"; then
        exit 1
    fi
fi

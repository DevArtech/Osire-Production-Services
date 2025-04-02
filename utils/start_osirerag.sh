#!/bin/bash

#SBATCH --job-name="OsireRAG Service - Slurm Job"
#SBATCH --partition=teaching
#SBATCH --nodes=1
#SBATCH --gres=gpu:t4:1
#SBATCH --cpus-per-gpu=4
#SBATCH --time=06:00:00
#SBATCH --output=slurm_output_placeholder.out  # temporary placeholder

# Now override the output programmatically
USER_OUTPUT_DIR="/home/$SLURM_JOB_USER/osire/output"
mkdir -p "$USER_OUTPUT_DIR"
exec > "$USER_OUTPUT_DIR/osirerag_${SLURM_JOB_ID}.out" 2>&1

## Default values
API_TOKEN=""

## Display usage information
usage() {
    echo "Usage: sbatch $0 -k <api_key>" >&2
    echo "  -k <api_key>      API key to set as API_TOKEN environment variable" >&2
    exit 1
}

## Parse command-line arguments
while getopts "k:m:" opt; do
    case $opt in
        k) API_TOKEN="$OPTARG" ;;
        *) usage ;;
    esac
done

## Check for required arguments
if [ -z "$API_TOKEN" ]; then
    echo "Error: API key (-k) is required." >&2
    usage
fi

## Function to find an open port, starting with a random user port (1024-49151)
find_port() {
    local start_port=1024
    local end_port=49151
    local random_port=$((RANDOM % (end_port - start_port + 1) + start_port))

    # Check the random port first
    if ! (echo > "/dev/tcp/localhost/$random_port") &>/dev/null; then
        echo "$random_port"
        return 0
    fi

    # If the random port is not available, check sequentially from start_port to end_port
    for ((port=start_port; port<=end_port; port++)); do
        if ! (echo > "/dev/tcp/localhost/$port") &>/dev/null; then
            echo "$port"
            return 0
        fi
    done

    echo "No open port found in the range $start_port-$end_port" >&2
    return 1
}

## SCRIPT START

echo "Starting OsireRAG service..."
echo "Executing node hostname: $(hostname)"

# Set hardcoded paths for osirerag
SERVICE_NAME="OsireRAG"
IMAGE_PATH="../containers/osirerag.sif"

echo "Service: $SERVICE_NAME"
echo "Container image: $IMAGE_PATH"

# Check if the image exists
if [ ! -f "$IMAGE_PATH" ]; then
    echo "Error: OsireRAG container image does not exist: $IMAGE_PATH" >&2
    echo "Please run setup.py first to build the container images." >&2
    exit 1
fi

# Find an open port and store it in a variable
PORT=$(find_port)
if [ $? -eq 0 ]; then
    echo "Found open port: $PORT"
else
    echo "Failed to find an open port. Exiting."
    exit 1
fi

# Determine the host and URLs
HOST=$(hostname)
export BASE_URL="/node/${HOST}.hpc.msoe.edu/${PORT}"
MODIFIED_URL=$(echo "$BASE_URL" | sed -e 's#^/node/##' -e 's#/[^/]*$##')

echo "BASE_URL: $BASE_URL"
echo "MODIFIED_URL: $MODIFIED_URL"

# Run the Singularity container with the specified command
echo "Running OsireRAG container..."
singularity exec \
    --nv \
    --network-args portmap=$PORT:$PORT \
    -B /data:/data \
    --env API_TOKEN="$API_TOKEN" \
    "$IMAGE_PATH" \
    uvicorn --app-dir /var/task/app main:app --port $PORT --host $MODIFIED_URL

echo "OsireRAG container execution finished."

## SCRIPT END 
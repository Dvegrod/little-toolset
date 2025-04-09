#!/bin/bash

# Script to generate Slurm job scripts based on available resources
#
# Author: Daniel Sergio Vega Rodriguez (USI PhD)
# (No responsability or liability over the execution of this script.)
#
# Date: April 8, 2025

# Function to display script header
function display_header() {
    clear
    echo "====================================================="
    echo "            SLURM JOB SCRIPT GENERATOR               "
    echo "====================================================="
    echo
}

# Function to get available partitions
function get_partitions() {
    echo "Fetching available partitions..."
    echo
    PARTITIONS=$(sinfo -h -o "%R" | sort | uniq)
    if [ -z "$PARTITIONS" ]; then
        echo "Error: Could not fetch partition information."
        exit 1
    fi
}

# Function to get available resources for a specific partition
function get_resources() {
    local partition=$1
    echo "Fetching resources for partition: $partition"
    
    # Get maximum nodes available in the partition
    MAX_NODES=$(sinfo -h -p $partition -o "%D" | sort -nr | head -n1)
    
    # Get CPUs per node
    CPUS_PER_NODE=$(sinfo -h -p $partition -o "%c" | sort -nr | head -n1)
    
    # Get memory per node
    MEM_PER_NODE=$(sinfo -h -p $partition -o "%m" | sort -nr | head -n1)
    
    # Get maximum time limit
    TIME_LIMIT=$(sinfo -h -p $partition -o "%l" | head -n1)
    
    echo "  - Maximum nodes: $MAX_NODES"
    echo "  - CPUs per node: $CPUS_PER_NODE"
    echo "  - Memory per node: $MEM_PER_NODE MB"
    echo "  - Time limit: $TIME_LIMIT"
    echo
}

# Function to prompt user for partition selection
function select_partition() {
    echo "Available partitions:"
    local i=1
    for p in $PARTITIONS; do
        echo "  $i) $p"
        i=$((i+1))
    done
    
    echo
    read -p "Select partition [1-$((i-1))]: " PARTITION_INDEX
    
    if ! [[ "$PARTITION_INDEX" =~ ^[0-9]+$ ]] || [ "$PARTITION_INDEX" -lt 1 ] || [ "$PARTITION_INDEX" -gt $((i-1)) ]; then
        echo "Invalid selection. Please try again."
        select_partition
        return
    fi
    
    # Convert selection to partition name
    local j=1
    for p in $PARTITIONS; do
        if [ $j -eq $PARTITION_INDEX ]; then
            SELECTED_PARTITION=$p
            break
        fi
        j=$((j+1))
    done
    
    # Get resources for selected partition
    get_resources $SELECTED_PARTITION
}

# Function to prompt user for job specifications
function get_job_specs() {
    # Job name
    read -p "Enter job name: " JOB_NAME
    
    # Number of nodes
    read -p "Enter number of nodes [1-$MAX_NODES]: " NUM_NODES
    if ! [[ "$NUM_NODES" =~ ^[0-9]+$ ]] || [ "$NUM_NODES" -lt 1 ] || [ "$NUM_NODES" -gt "$MAX_NODES" ]; then
        echo "Invalid number of nodes. Setting to 1."
        NUM_NODES=1
    fi
    
    # Tasks per node
    read -p "Enter tasks per node [1-$CPUS_PER_NODE]: " TASKS_PER_NODE
    if ! [[ "$TASKS_PER_NODE" =~ ^[0-9]+$ ]] || [ "$TASKS_PER_NODE" -lt 1 ] || [ "$TASKS_PER_NODE" -gt "$CPUS_PER_NODE" ]; then
        echo "Invalid number of tasks per node. Setting to 1."
        TASKS_PER_NODE=1
    fi
    
    # Time limit
    read -p "Enter time limit (format: HH:MM:SS or D-HH:MM:SS): " TIME_LIMIT_INPUT
    
    # Output file
    read -p "Enter output file name [default: slurm-%j.out]: " OUTPUT_FILE
    if [ -z "$OUTPUT_FILE" ]; then
        OUTPUT_FILE="slurm-%j.out"
    fi
    
    # Email notifications
    read -p "Do you want email notifications? (y/n): " EMAIL_NOTIFY
    if [[ "$EMAIL_NOTIFY" =~ ^[Yy]$ ]]; then
        read -p "Enter email address: " EMAIL_ADDRESS
        read -p "Enter notification types (comma-separated: BEGIN,END,FAIL,ALL): " NOTIFY_TYPES
        if [ -z "$NOTIFY_TYPES" ]; then
            NOTIFY_TYPES="END,FAIL"
        fi
    fi
    
    
    # Command to run
    echo "Enter the command(s) to run (Ctrl+D to finish):"
    COMMANDS=$(cat)
}

# Function to prompt user for extra job specifications
function get_job_specs_extra() {
    echo
    echo "======= Advanced Options ======="
    echo

    # Memory per node
    read -p "Enter memory per node in MB [1-$MEM_PER_NODE] (ENTER for undetermined): " MEM_REQUEST
    if ! [[ "$MEM_REQUEST" =~ ^[0-9]+$ ]] || [ "$MEM_REQUEST" -lt 1 ] || [ "$MEM_REQUEST" -gt "$MEM_PER_NODE" ]; then
        echo "Setting to not defined."
        MEM_REQUEST="NULL"
    fi

    # Ask if user wants to set constraints
    read -p "Do you want to specify node constraints/features? (y/n): " USE_CONSTRAINTS
    if [[ "$USE_CONSTRAINTS" =~ ^[Yy]$ ]]; then
        # Fetch available constraints from sinfo
        AVAIL_CONSTRAINTS=$(sinfo -h -o "%f" | grep -v "none" | sort | uniq | tr -s ' ' | tr ' ' ',')
        if [ ! -z "$AVAIL_CONSTRAINTS" ]; then
            echo "Available constraints: $AVAIL_CONSTRAINTS"
            read -p "Enter constraints (comma-separated): " CONSTRAINTS
        else
            read -p "Enter constraints (no available constraints detected, enter manually): " CONSTRAINTS
        fi
    fi

    # Ask for exclusive node access
    read -p "Do you want exclusive node access? (y/n): " EXCLUSIVE

    # Ask for GPU resources
    read -p "Do you need GPUs? (y/n): " NEED_GPUS
    if [[ "$NEED_GPUS" =~ ^[Yy]$ ]]; then
        # Try to get available GPU types
        GPU_TYPES=$(sinfo -h -o "%G" | grep -v "none" | sort | uniq | tr -s ' ' | tr ' ' ',')
        if [ ! -z "$GPU_TYPES" ]; then
            echo "Available GPU types: $GPU_TYPES"
        fi
        read -p "Enter number of GPUs per node: " GPUS_PER_NODE
        read -p "Enter GPU type (if applicable): " GPU_TYPE
    fi

    # Ask for specific CPU types
    read -p "Do you want to specify CPU architecture? (y/n): " SPECIFIC_CPU
    if [[ "$SPECIFIC_CPU" =~ ^[Yy]$ ]]; then
        read -p "Enter CPU architecture constraint: " CPU_ARCH
    fi

    # Ask for account information
    read -p "Do you want to specify an account? (y/n): " USE_ACCOUNT
    if [[ "$USE_ACCOUNT" =~ ^[Yy]$ ]]; then
        # Try to get available accounts
        if command -v sacctmgr &> /dev/null; then
            USER_ACCOUNTS=$(sacctmgr -n list associations user=$USER format=account | sort | uniq)
            if [ ! -z "$USER_ACCOUNTS" ]; then
                echo "Available accounts: $USER_ACCOUNTS"
            fi
        fi
        read -p "Enter account name: " ACCOUNT_NAME
    fi

    # Ask for QOS
    read -p "Do you want to specify Quality of Service (QOS)? (y/n): " USE_QOS
    if [[ "$USE_QOS" =~ ^[Yy]$ ]]; then
        # Try to get available QOS options
        if command -v sacctmgr &> /dev/null; then
            QOS_OPTIONS=$(sacctmgr -n show qos format=name | sort)
            if [ ! -z "$QOS_OPTIONS" ]; then
                echo "Available QOS options: $QOS_OPTIONS"
            fi
        fi
        read -p "Enter QOS name: " QOS_NAME
    fi

    # Ask for array job
    read -p "Do you want to create an array job? (y/n): " ARRAY_JOB
    if [[ "$ARRAY_JOB" =~ ^[Yy]$ ]]; then
        read -p "Enter array indices (e.g., 1-10 or 1,3,5-7): " ARRAY_INDICES
    fi

    # Ask for dependency
    read -p "Do you want to add job dependencies? (y/n): " USE_DEPENDENCY
    if [[ "$USE_DEPENDENCY" =~ ^[Yy]$ ]]; then
        echo "Dependency types: after, afterany, afternotok, afterok"
        read -p "Enter dependency (e.g., afterok:123456): " DEPENDENCY
    fi

    # Ask for custom environment variables
    read -p "Do you want to set custom environment variables? (y/n): " SET_ENV_VARS
    if [[ "$SET_ENV_VARS" =~ ^[Yy]$ ]]; then
        echo "Enter environment variables (format: VAR=value, one per line, empty line to finish):"
        ENV_VARS=""
        while true; do
            read ENV_VAR
            if [ -z "$ENV_VAR" ]; then
                break
            fi
            ENV_VARS+="$ENV_VAR"$'\n'
        done
    fi

    # Ask for modules to load
    read -p "Do you want to load modules? (y/n): " LOAD_MODULES
    if [[ "$LOAD_MODULES" =~ ^[Yy]$ ]]; then
        # Try to list available modules
        if command -v module &> /dev/null; then
            echo "Checking available modules..."
            module avail 2>&1 | head -n 15
            echo "..."
        fi
        echo "Enter modules to load (one per line, empty line to finish):"
        MODULES=""
        while true; do
            read MODULE
            if [ -z "$MODULE" ]; then
                break
            fi
            MODULES+="module load $MODULE"$'\n'
        done
    fi
}

# Function to generate the Slurm script
function generate_script() {
    SCRIPT_NAME="${JOB_NAME:-job}_slurm.sh"
    
    echo "Generating Slurm script: $SCRIPT_NAME"
    
    cat > "$SCRIPT_NAME" << EOL
#!/bin/bash
#SBATCH --job-name=${JOB_NAME:-job}
#SBATCH --partition=${SELECTED_PARTITION}
#SBATCH --nodes=${NUM_NODES:-1}
#SBATCH --ntasks-per-node=${TASKS_PER_NODE:-1}
#SBATCH --mem=${MEM_REQUEST:-1000}
#SBATCH --output=${OUTPUT_FILE:-slurm-%j.out}
EOL

    # Add time limit if specified
    if [ ! -z "$TIME_LIMIT_INPUT" ]; then
        echo "#SBATCH --time=${TIME_LIMIT_INPUT}" >> "$SCRIPT_NAME"
    fi
    
    # Add email notifications if requested
    if [[ "$EMAIL_NOTIFY" =~ ^[Yy]$ ]]; then
        echo "#SBATCH --mail-user=${EMAIL_ADDRESS}" >> "$SCRIPT_NAME"
        echo "#SBATCH --mail-type=${NOTIFY_TYPES}" >> "$SCRIPT_NAME"
    fi
    
    # Add standard header
    cat >> "$SCRIPT_NAME" << EOL

echo "Job started on \$(hostname) at \$(date)"
echo "Job ID: \$SLURM_JOB_ID"
echo "Nodes: \$SLURM_JOB_NODELIST"
echo "----------------------------------------------------------------"

# Load modules
# module load <module_name>

# Set environment variables
# export VAR=value

EOL

    # Add user commands
    echo "# User commands" >> "$SCRIPT_NAME"
    echo "$COMMANDS" >> "$SCRIPT_NAME"
    
    # Add footer
    cat >> "$SCRIPT_NAME" << EOL

echo "----------------------------------------------------------------"
echo "Job completed at \$(date)"
EOL

    # Make the script executable
    chmod +x "$SCRIPT_NAME"
    
    echo "Script generated successfully: $SCRIPT_NAME"
    echo "You can submit your job with: sbatch $SCRIPT_NAME"
}

# Main script execution
display_header
get_partitions
select_partition
get_job_specs
generate_script

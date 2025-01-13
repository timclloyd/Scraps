#!/bin/bash

# Define the source directory and output file
SOURCE_DIR="../MyiPadSketchbook"
OUTPUT_FILE="all-app-code.swift"

# Remove the output file if it already exists
rm -f "$OUTPUT_FILE"

# Find all Swift files in the source directory and its subdirectories
find "$SOURCE_DIR" -name "*.swift" | while read -r file; do
    # Get the filename with its parent folder
    relative_path=${file#"$SOURCE_DIR/"}
    folder_and_file=$(dirname "$relative_path")/$(basename "$file")
    
    # Write the start comment
    echo "// Start of $folder_and_file" >> "$OUTPUT_FILE"
    
    # Append the contents of the file
    cat "$file" >> "$OUTPUT_FILE"
    
    # Write the end comment
    echo "// End of $folder_and_file" >> "$OUTPUT_FILE"
    
    # Add a newline for readability
    echo "" >> "$OUTPUT_FILE"
done

echo "All Swift files have been concatenated into $OUTPUT_FILE"
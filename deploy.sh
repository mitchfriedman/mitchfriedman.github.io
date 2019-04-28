#!/bin/bash

echo -e "\033[0;32mDeploying updates to GitHub...\033[0m"

cd raw

# Build the project.
hugo 

cp -r public/* ../

cd ../

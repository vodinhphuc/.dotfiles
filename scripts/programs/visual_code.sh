! command -v code &> /dev/null
if ! command -v code &> /dev/null; then
    echo "Installing: visual studio code..."
    sudo snap install --classic code
else
     echo "Already installed: visual studio code"
fi


#!/bin/bash
# ── Mobile Store App Launcher (macOS) ──────────────────────────────────────
# Double-click this file to start the app. It will open in your browser.

cd "$(dirname "$0")"

# Activate conda base environment (where all packages are installed)
if [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
    source "$HOME/miniconda3/etc/profile.d/conda.sh"
    conda activate base
elif [ -f "$HOME/anaconda3/etc/profile.d/conda.sh" ]; then
    source "$HOME/anaconda3/etc/profile.d/conda.sh"
    conda activate base
fi

echo ""
echo "  📱 Starting Mobile Store App..."
echo "  Opening http://localhost:8501 in your browser."
echo "  Press Ctrl+C in this window to stop the app."
echo ""

streamlit run app.py --server.headless false

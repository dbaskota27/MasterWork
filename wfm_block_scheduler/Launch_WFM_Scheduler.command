#!/bin/bash
cd "$(dirname "$0")"
source ~/miniconda3/etc/profile.d/conda.sh
conda activate mycondaenv
streamlit run app.py

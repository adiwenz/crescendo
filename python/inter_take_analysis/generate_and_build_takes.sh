python generate_take.py ../audio_files/LV35_01.wav --output takes/LV35_01.csv --take_name LV35_01
python generate_take.py ../audio_files/LV35_02.wav --output takes/LV35_02.csv --take_name LV35_02
python generate_take.py ../audio_files/LV35_03.wav --output takes/LV35_03.csv --take_name LV35_03
python generate_take.py ../audio_files/LV35_04.wav --output takes/LV35_04.csv --take_name LV35_04
python build_takes_index.py --takes_dir takes

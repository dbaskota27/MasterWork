Key Functionalities
The notebook is divided into several sections, each addressing a specific aspect of contact center forecasting. Below is a breakdown of what the code does:

Call Arrival Pattern (CAP) Forecasting:
Objective: Predicts the distribution of call arrivals across 30-minute intervals for each day.

Process:
Retrieves historical call data from an Avaya statistics database (get_call_data).
Handles missing data by filling gaps with data from the previous week’s same time interval (fill_missing_calls).
Engineers features like day-of-week, month, year, holidays, and lag features (e.g., prior weeks, same time last year) (feature_engineering).
Uses a machine learning model (e.g., RandomForestRegressor) to predict the percentage of daily call volume per interval (future_projection).
Normalizes predictions to ensure the sum of percentages per day equals 1 (normalize).
Integrates U.S. federal holidays and Easter to adjust for special dates (set_easter_holiday).
Stores predictions in a SQL database for reporting (insert_sql).

Call Volume Forecasting:
Objective: Projects total daily call volumes for future dates.

Process:
Fetches daily call data for a client or specific team (get_call_data).
Applies feature engineering, including cyclical features (e.g., sine/cosine of day-of-year), rolling averages, and historical lags (add_feature_columns).
Uses RandomForestRegressor with grid search and time-series cross-validation to predict call volumes (future_projection).
Handles outliers by clipping extreme values based on quantiles.
Allows for manual percentage increases in predictions (e.g., to account for expected growth).
Generates a DataFrame with predicted call volumes for the specified date range.

Year-over-Year Call Volume Visualization:
Objective: Visualizes historical and predicted call volumes by month across multiple years.
Process:
Combines historical data (get_call_data) with predicted data (future_projection) (plot_yoy_call_volume_with_2025).
Aggregates call volumes by month and year, creating a pivot table.
Plots a line chart with markers for each month, annotated with call volume values.
Ensures no overlap between historical and predicted data to maintain accuracy.

Average Handle Time (AHT) Forecasting:
Objective: Predicts the average time agents spend handling calls in 2-hour intervals.
Process:
Retrieves AHT data from the Avaya database (get_call_data).
Fills missing AHT values using the previous week’s data or a contractual threshold for specific intervals (fill_missing_AHT).
Engineers features similar to CAP forecasting, including time-based and holiday flags (feature_engineering).
Trains an ML model to predict AHT for future intervals (future_projection).
Updates the database with predicted AHT values (update_sql).

FTE Estimation Using Erlang-C:
Objective: Calculates the number of agents (FTE) required to meet SLA targets.
Process:
Combines CAP, call volume, and AHT predictions to estimate transactions per interval (sql_cvp, sql_cap).
Uses the Erlang-C model to compute required positions based on:
Target transactions (calls per interval).
Average Speed of Answer (ASA) from client conditions.
AHT, shrinkage (e.g., 35%), service level (e.g., 80%), and maximum occupancy (e.g., 85%) (ErlangC).
Adjusts shrinkage if occupancy falls below 60% to optimize staffing.
Applies a rolling mean to smooth FTE projections (roll).
Inserts FTE projections into the database (insert).

Database Integration:
Objective: Seamlessly pulls and stores data for scalability and reporting.
Process:
Connects to Avaya and reporting databases using pyodbc (get_db_avaya_stats, get_db_dictionary, get_db_Client_data_import).
Executes SQL queries to retrieve historical data, client configurations, and hours of operation (HoOPS) (get_hoops_for_test_frame).
Upserts predictions (CAP, AHT, FTE) into the database in batches of 500 rows to manage large datasets (insert_sql, update_sql).
Time Series and Feature Engineering:
Creates complete time series with no gaps using get_date_range and get_hoops_for_test_frame.
Converts time formats to integers for ML compatibility (time_to_int).
Incorporates advanced features like PCA for dimensionality reduction in call volume forecasting (prep_for_ML, create_test_frame).

Key Features
ML-Based Predictions: Uses scikit-learn’s RandomForestRegressor with grid search for robust forecasting.
Holiday Awareness: Accounts for U.S. federal holidays and Easter to adjust predictions.
Flexible Time Intervals: Supports 30-minute intervals for CAP and 2-hour intervals for AHT.
Erlang-C Integration: Applies queuing theory for accurate staffing calculations.
Visualization: Generates clear year-over-year call volume plots using Matplotlib.
Scalability: Handles large datasets with batch database operations and modular functions.
Extensibility: Supports any scikit-learn-compatible ML model and customizable client parameters.

Use Cases
Workforce Management: Projects staffing needs up to 9 months out based on call volumes and SLAs.
Contact Center Analysts: Analyzes past performance and simulates SLA scenarios.
Operations Leadership: Supports data-informed decisions for shift planning, hiring, and outsourcing.

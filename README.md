🧠 Competitive Programming Practice Tracker
A Full-Stack DBMS Project using MySQL + Streamlit + Python
🚀 Overview

The Competitive Programming Practice Tracker is a complete database-driven analytical platform designed to monitor competitive programming performance across platforms such as LeetCode, Codeforces, HackerRank, CodeChef, and AtCoder.

This system integrates:
✔ MySQL Relational Database
✔ Streamlit Interactive Frontend
✔ Python Backend Logic
✔ Triggers, Stored Procedures, Views & Normalization Concepts

This project is ideal for DBMS coursework, academic evaluation, and resume-strengthening portfolio development.
📌 Key Features
🎯 User Performance Tracking

Tracks problems solved across multiple platforms

Records verdicts (AC, WA, TLE, RTE)

Maintains submission attempts, languages, and timestamps

🏷️ Tag-Wise Topic Analytics

Evaluate user strengths and weaknesses

Topic-wise acceptance ratios

Problem distribution across tags

🧾 Leaderboard & Global Insights

Ranks users by solved problems

Calculates accuracy and performance metrics

Provides platform-wise analytics

📊 Visual Streamlit Dashboards

Summary cards for users, problems, submissions

Interactive tables and filters

Bar charts and performance plots

Recent activity timeline

📦 Competitive Programming Practice Tracker
│── app.py                 # Backend logic (Flask or SQL connector)
│── streamlit_frontend.py  # Streamlit dashboard UI
│── dbms.sql               # MySQL schema, triggers, procedures, views
│── requirements.txt
│── README.md
│
├── static/                # CSS, icons, images
├── templates/             # Optional HTML templates for Flask
├── models/                # Optional ORM mappings
├── routes/                # Optional modular API endpoints
└── screenshots/           # Output screenshots for readme/report


🛠️ Installation & Setup Instructions
🔧 1. Install Dependencies
pip install -r requirements.txt

🗄️ 2. Import SQL Schema

Open MySQL Workbench, then run:

SOURCE dbms.sql;

▶️ 3. Run the Streamlit Application
streamlit run streamlit_frontend.py


The dashboard will open automatically in your browser.

📈 Future Enhancements

Automatic scraping from LeetCode / Codeforces profiles

User authentication (JWT / OAuth)

Dark-mode theme in Streamlit

Mobile-friendly interface

Daily email reports
⭐ Acknowledgments

This project demonstrates a complete example of integrating:
Database Management → Backend Logic → Data Analytics → Frontend UI.
It successfully showcases DBMS concepts such as triggers, procedures, views, joins, normalization, and real-time analytics.

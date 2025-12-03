"""
Streamlit frontend for Competitive Coding Progress Tracker
File: streamlit_frontend.py

Features:
- Dashboard: KPIs, recent activity, charts
- Leaderboard: sortable table from vw_leaderboard
- Problems: searchable list, tag filters, open problem link
- Submissions: recent submissions, add a submission form (writes to DB)
- Tag Analysis: tag summary table + charts
- Admin: run stored procedure to recompute user_tag_stats, view audit_log

Usage:
1. pip install streamlit sqlalchemy pymysql pandas plotly
2. Set env:  DATABASE_URL="mysql+pymysql://user:pass@localhost:3306/cp_tracker"
3. Run:      streamlit run streamlit_frontend.py
"""

import os
from datetime import datetime
import pandas as pd
import sqlalchemy
import streamlit as st
import plotly.express as px

# ---------------------------
# Config
# ---------------------------
st.set_page_config(page_title="Competitive Coding Tracker", layout="wide")

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "mysql+pymysql://root:root@localhost:3306/cp_tracker"
)

# ---------------------------
# Helpers
# ---------------------------
@st.cache_resource
def get_engine():
    """Create SQLAlchemy engine (cached safely)."""
    return sqlalchemy.create_engine(DATABASE_URL, pool_pre_ping=True)

def query_sql(sql: str, params=None) -> pd.DataFrame:
    """Always fetch fresh data (no caching for dynamic filters)."""
    engine = get_engine()
    with engine.connect() as conn:
        return pd.read_sql(sql, conn, params=params)

def run_write(sql: str, params=None):
    engine = get_engine()
    with engine.begin() as conn:
        conn.execute(sqlalchemy.text(sql), params or {})

# ---------------------------
# Sidebar
# ---------------------------
st.sidebar.title("Competitive Coding — Control")
page = st.sidebar.radio(
    "Go to",
    ["Dashboard", "Leaderboard", "Problems", "Submissions", "Tag Analysis", "Admin"]
)

platforms_df = query_sql("SELECT platform_name FROM Platforms")
platforms = platforms_df["platform_name"].tolist() if not platforms_df.empty else []
selected_platform = st.sidebar.selectbox("Platform", ["All"] + platforms, index=0)

tags_df = query_sql("SELECT tag_name FROM Tags")
tags = tags_df["tag_name"].tolist() if not tags_df.empty else []
selected_tag = st.sidebar.selectbox("Tag", ["All"] + tags, index=0)

search_text = st.sidebar.text_input("Quick search (problem / user)")

st.sidebar.markdown("---")
st.sidebar.markdown("Built with ❤️ — Streamlit")

# ---------------------------
# Dashboard
# ---------------------------
if page == "Dashboard":
    st.title("📊 Dashboard")

    col1, col2, col3, col4 = st.columns(4)

    users_count = query_sql("SELECT COUNT(*) AS cnt FROM Users")["cnt"].iloc[0]
    problems_count = query_sql("SELECT COUNT(*) AS cnt FROM Problems")["cnt"].iloc[0]
    subs_count = query_sql("SELECT COUNT(*) AS cnt FROM Submissions")["cnt"].iloc[0]
    accepted_count = query_sql(
        "SELECT SUM(verdict='Accepted') AS cnt FROM Submissions"
    )["cnt"].iloc[0]
    accepted_rate = round((accepted_count / subs_count) * 100, 2) if subs_count else 0

    col1.metric("Users", users_count)
    col2.metric("Problems", problems_count)
    col3.metric("Submissions", subs_count)
    col4.metric("Global Accept Rate", f"{accepted_rate}%")

    st.markdown("---")

    st.subheader("Recent Submissions")
    recent_sql = """
      SELECT s.submission_id, u.username, p.title, s.verdict, s.submission_date,
             s.language, s.attempt_no
      FROM Submissions s
      JOIN Users u ON s.user_id = u.user_id
      JOIN Problems p ON s.problem_id = p.problem_id
      ORDER BY s.submission_date DESC
      LIMIT 25
    """
    recent_df = query_sql(recent_sql)
    st.dataframe(recent_df)

    st.markdown("---")
    st.subheader("Submissions — Last 8 Weeks")
    trend_sql = """
      SELECT YEARWEEK(submission_date,1) AS yw, COUNT(*) AS submissions
      FROM Submissions
      WHERE submission_date >= CURDATE() - INTERVAL 8 WEEK
      GROUP BY yw ORDER BY yw DESC
    """
    trend_df = query_sql(trend_sql)
    if not trend_df.empty:
        trend_df["week"] = trend_df["yw"].astype(str)
        fig = px.bar(trend_df.sort_values("week"),
                     x="week", y="submissions",
                     labels={"week": "YearWeek", "submissions": "Submissions"})
        st.plotly_chart(fig, use_container_width=True)
    else:
        st.info("No recent submissions to chart.")

# ---------------------------
# Leaderboard
# ---------------------------
elif page == "Leaderboard":
    st.title("🏆 Leaderboard")
    lb_df = query_sql("SELECT * FROM vw_leaderboard")

    if search_text:
        lb_df = lb_df[lb_df["username"].str.contains(search_text, case=False, na=False)]

    # fallback for missing accuracy column
    if "accuracy" not in lb_df.columns:
        lb_df["accuracy"] = 0

    lb_df = lb_df.sort_values(by=["total_solved", "accuracy"],
                              ascending=[False, False]).reset_index(drop=True)
    st.dataframe(lb_df)

    st.subheader("Top Solvers")
    top = lb_df.sort_values("total_solved", ascending=False).head(10)
    if not top.empty:
        fig = px.bar(top, x="username", y="total_solved", text="total_solved")
        st.plotly_chart(fig, use_container_width=True)

# ---------------------------
# Problems
# ---------------------------
elif page == "Problems":
    st.title("📚 Problems")

    problems_sql = """
      SELECT p.problem_id, p.title, p.difficulty,
             pl.platform_name, p.problem_url
      FROM Problems p
      JOIN Platforms pl ON p.platform_id = pl.platform_id
    """
    p_df = query_sql(problems_sql)

    if selected_platform != "All":
        p_df = p_df[p_df["platform_name"] == selected_platform]

    if selected_tag != "All":
        tag_sql = """
        SELECT p.problem_id
        FROM Problems p
        JOIN Problem_Tag pt ON p.problem_id = pt.problem_id
        JOIN Tags t ON pt.tag_id = t.tag_id
        WHERE t.tag_name = %s
        """
        engine = get_engine()
        with engine.connect() as conn:
            tag_ids = pd.read_sql(tag_sql, conn, params=(selected_tag,))
        p_df = p_df[p_df["problem_id"].isin(tag_ids["problem_id"].tolist())]

    if search_text:
        p_df = p_df[p_df["title"].str.contains(search_text, case=False, na=False)]

    st.dataframe(p_df[["problem_id", "title", "difficulty",
                       "platform_name", "problem_url"]])

    sel = st.number_input("Open problem_id to view tags (0 = none)", value=0, min_value=0)
    if sel > 0:
        tags = query_sql(
            "SELECT t.tag_name FROM Tags t "
            "JOIN Problem_Tag pt ON t.tag_id = pt.tag_id "
            "WHERE pt.problem_id = %s",
            params=[sel]
        )
        st.write("Tags:", tags["tag_name"].tolist())

# ---------------------------
# Submissions
# ---------------------------
elif page == "Submissions":
    st.title("✍️ Submissions")
    st.subheader("Add Submission")

    with st.form("add_sub"):
        users = query_sql("SELECT user_id, username FROM Users")
        user = st.selectbox("User", users["username"].tolist())
        user_id = users.loc[users["username"] == user, "user_id"].iloc[0]

        problems = query_sql("SELECT problem_id, title FROM Problems")
        problem = st.selectbox("Problem", problems["title"].tolist())
        problem_id = problems.loc[problems["title"] == problem, "problem_id"].iloc[0]

        verdict = st.selectbox("Verdict", ["Accepted", "Wrong Answer", "TLE", "RTE"])
        lang = st.text_input("Language", value="Python")
        notes = st.text_area("Notes")
        submitted = st.form_submit_button("Submit")

    if submitted:
        insert_sql = (
            "INSERT INTO Submissions (user_id, problem_id, verdict, language, notes) "
            "VALUES (:uid, :pid, :verdict, :lang, :notes)"
        )
        try:
            run_write(insert_sql, {
                "uid": user_id, "pid": problem_id,
                "verdict": verdict, "lang": lang, "notes": notes
            })
            st.success("Submission recorded — triggers will update counts and audit_log.")
        except Exception as e:
            st.error(f"Failed to insert submission: {e}")

    st.markdown("---")
    st.subheader("Recent Submissions")
    subs_df = query_sql("""
      SELECT s.submission_id, u.username, p.title, s.verdict, s.submission_date
      FROM Submissions s
      JOIN Users u ON s.user_id = u.user_id
      JOIN Problems p ON s.problem_id = p.problem_id
      ORDER BY s.submission_date DESC
      LIMIT 100
    """)
    st.dataframe(subs_df)

# ---------------------------
# Tag Analysis
# ---------------------------
elif page == "Tag Analysis":
    st.title("🔖 Tag Analysis")
    tag_df = query_sql("SELECT * FROM vw_tag_summary")

    if selected_tag != "All":
        tag_df = tag_df[tag_df["tag_name"] == selected_tag]

    # Compute accepted_rate if missing
    if "accepted_rate" not in tag_df.columns:
        if all(c in tag_df.columns for c in ["accepted_submissions", "total_submissions"]):
            tag_df["accepted_rate"] = (
                tag_df["accepted_submissions"] / tag_df["total_submissions"]
            ).fillna(0) * 100
        else:
            tag_df["accepted_rate"] = 0

    st.dataframe(tag_df)

    st.subheader("Tag Acceptance Rates")
    if not tag_df.empty:
        fig = px.bar(
            tag_df.sort_values("accepted_rate", ascending=False),
            x="tag_name", y="accepted_rate", text="accepted_rate",
            title="Tag Acceptance Rates (%)"
        )
        st.plotly_chart(fig, use_container_width=True)
    else:
        st.info("No tag data available.")

# ---------------------------
# Admin
# ---------------------------
elif page == "Admin":
    st.title("🛠 Admin")
    st.write("Be careful — admin actions affect DB.")

    if st.button("Recompute user_tag_stats (CALL sp_compute_user_tag_stats())"):
        try:
            engine = get_engine()
            with engine.begin() as conn:
                conn.execute(sqlalchemy.text("CALL sp_compute_user_tag_stats()"))
            st.success("Stored procedure executed — user_tag_stats updated.")
        except Exception as e:
            st.error(f"Failed to run stored procedure: {e}")

    st.markdown("---")
    st.subheader("Audit Log (last 200)")
    try:
        audit = query_sql("SELECT * FROM audit_log ORDER BY changed_at DESC LIMIT 200")
        st.dataframe(audit)
    except Exception as e:
        st.error(f"Could not fetch audit log: {e}")

# ---------------------------
# Footer
# ---------------------------
st.sidebar.markdown("---")
st.sidebar.caption(f"Updated: {datetime.utcnow().isoformat()} UTC")
st.markdown("<style>iframe[title='stMarkdown']{border-radius:12px}</style>", unsafe_allow_html=True)

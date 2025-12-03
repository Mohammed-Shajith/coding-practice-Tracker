-- Competitive Coding Progress Tracker (MySQL 8.x)
-- Run as a single script. Wrap in a transaction or run step-by-step.

-- =========================
-- 1. CLEANUP (safe to skip if fresh DB)
-- =========================
DROP TABLE IF EXISTS user_tag_stats;
DROP TABLE IF EXISTS audit_log;
DROP TABLE IF EXISTS submission_metrics;
DROP TABLE IF EXISTS Submissions;
DROP TABLE IF EXISTS Problem_Tag;
DROP TABLE IF EXISTS Tags;
DROP TABLE IF EXISTS Problems;
DROP TABLE IF EXISTS Platforms;
DROP TABLE IF EXISTS Users;

-- =========================
-- 2. SCHEMA
-- =========================

CREATE TABLE Users (
  user_id INT AUTO_INCREMENT PRIMARY KEY,
  username VARCHAR(100) NOT NULL,
  email VARCHAR(255) UNIQUE NOT NULL,
  join_date DATETIME DEFAULT CURRENT_TIMESTAMP,
  total_solved INT DEFAULT 0,
  total_submissions INT DEFAULT 0,
  -- simple constraint example
  CHECK (CHAR_LENGTH(username) > 0)
);

CREATE TABLE Platforms (
  platform_id INT AUTO_INCREMENT PRIMARY KEY,
  platform_name VARCHAR(100) NOT NULL UNIQUE,
  api_url VARCHAR(512),
  notes VARCHAR(512)
);

CREATE TABLE Problems (
  problem_id INT AUTO_INCREMENT PRIMARY KEY,
  platform_id INT NOT NULL,
  platform_problem_id VARCHAR(100), -- id on that platform
  title VARCHAR(255) NOT NULL,
  difficulty ENUM('Easy','Medium','Hard') DEFAULT 'Medium',
  problem_url VARCHAR(512),
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (platform_id) REFERENCES Platforms(platform_id) ON DELETE CASCADE
);

CREATE TABLE Tags (
  tag_id INT AUTO_INCREMENT PRIMARY KEY,
  tag_name VARCHAR(100) NOT NULL UNIQUE
);

-- many-to-many Problem <-> Tag
CREATE TABLE Problem_Tag (
  problem_id INT NOT NULL,
  tag_id INT NOT NULL,
  PRIMARY KEY (problem_id, tag_id),
  FOREIGN KEY (problem_id) REFERENCES Problems(problem_id) ON DELETE CASCADE,
  FOREIGN KEY (tag_id) REFERENCES Tags(tag_id) ON DELETE CASCADE
);

CREATE TABLE Submissions (
  submission_id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  problem_id INT NOT NULL,
  submission_date DATETIME DEFAULT CURRENT_TIMESTAMP,
  verdict VARCHAR(50) NOT NULL, -- e.g., Accepted, Wrong Answer, TLE
  time_taken_ms INT, -- execution time
  language VARCHAR(50),
  attempt_no INT DEFAULT 1,
  notes VARCHAR(512),
  FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE,
  FOREIGN KEY (problem_id) REFERENCES Problems(problem_id) ON DELETE CASCADE,
  INDEX idx_user (user_id),
  INDEX idx_problem (problem_id),
  INDEX idx_verdict (verdict)
);

-- Lightweight audit log for changes to submissions (trigger target)
CREATE TABLE audit_log (
  audit_id INT AUTO_INCREMENT PRIMARY KEY,
  table_name VARCHAR(100),
  op_type ENUM('INSERT','UPDATE','DELETE'),
  changed_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  changed_by INT NULL,
  row_id INT NULL,
  details JSON NULL
);

-- Precomputed per-user tag stats (will be filled by SP)
CREATE TABLE user_tag_stats (
  uts_id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  tag_id INT NOT NULL,
  attempts INT DEFAULT 0,
  accepted INT DEFAULT 0,
  accepted_rate DECIMAL(6,4) AS (CASE WHEN attempts=0 THEN 0 ELSE accepted/attempts END) STORED,
  last_updated DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE (user_id, tag_id),
  FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE,
  FOREIGN KEY (tag_id) REFERENCES Tags(tag_id) ON DELETE CASCADE
);

-- Optional helper metrics table (example)
CREATE TABLE submission_metrics (
  metric_id INT AUTO_INCREMENT PRIMARY KEY,
  metric_date DATE,
  platform_id INT,
  total_submissions INT,
  total_accepted INT,
  FOREIGN KEY (platform_id) REFERENCES Platforms(platform_id)
);

-- =========================
-- 3. SAMPLE DATA
-- =========================

INSERT INTO Users (username, email) VALUES
('alice','alice@example.com'),
('bob','bob@example.com'),
('charlie','charlie@example.com');

INSERT INTO Platforms (platform_name, api_url, notes) VALUES
('LeetCode','https://leetcode.com','Popular coding site'),
('CodeChef','https://codechef.com','Contest platform'),
('AtCoder','https://atcoder.jp','Japanese contests');

INSERT INTO Problems (platform_id, platform_problem_id, title, difficulty, problem_url) VALUES
(1,'1','Two Sum','Easy','https://leetcode.com/problems/two-sum'),
(1,'2','Add Two Numbers','Medium','https://leetcode.com/problems/add-two-numbers'),
(2,'FLOW001','Sum in Flow','Easy','https://codechef.com/problems/FLOW001'),
(3,'abc001','Example Problem','Hard','https://atcoder.jp/abc001');

INSERT INTO Tags (tag_name) VALUES ('Array'),('LinkedList'),('Math'),('DP'),('Graph');

-- map problems to tags
INSERT INTO Problem_Tag (problem_id, tag_id) VALUES
(1,1), -- Two Sum -> Array
(2,2), -- Add Two Numbers -> LinkedList
(3,3), -- Flow -> Math
(4,4); -- abc001 -> DP

-- submissions sample
INSERT INTO Submissions (user_id, problem_id, verdict, time_taken_ms, language, attempt_no) VALUES
(1,1,'Accepted',34,'Python',1),
(1,2,'Wrong Answer',0,'C++',1),
(1,2,'Accepted',112,'C++',2),
(2,1,'Wrong Answer',0,'Python',1),
(2,3,'Accepted',20,'C',1),
(3,4,'Wrong Answer',0,'Python',1),
(3,4,'Wrong Answer',0,'Python',2);

-- Update users with basic counters for sample (could be derived but stored for fast reads)
UPDATE Users u
LEFT JOIN (
  SELECT user_id,
         SUM(verdict='Accepted') AS solved_count,
         COUNT(*) AS total_subs
  FROM Submissions GROUP BY user_id
) s ON u.user_id = s.user_id
SET u.total_solved = IFNULL(s.solved_count,0), u.total_submissions = IFNULL(s.total_subs,0);

-- =========================
-- 4. TRIGGERS
--   - audit_log on INSERT/UPDATE/DELETE for Submissions
--   - BEFORE INSERT on Submissions: set attempt_no automatically
--   - AFTER INSERT on Submissions: update Users counters
-- =========================

-- AUDIT trigger for INSERT
DELIMITER $$
CREATE TRIGGER trg_submissions_insert_audit
AFTER INSERT ON Submissions
FOR EACH ROW
BEGIN
  INSERT INTO audit_log (table_name, op_type, row_id, details)
  VALUES ('Submissions','INSERT', NEW.submission_id,
          JSON_OBJECT('user_id',NEW.user_id,'problem_id',NEW.problem_id,'verdict',NEW.verdict,'attempt_no',NEW.attempt_no));
END$$
DELIMITER ;

-- BEFORE INSERT: calculate attempt_no as 1 + max previous attempt for (user,problem)
DELIMITER $$
CREATE TRIGGER trg_submissions_before_insert_attempt
BEFORE INSERT ON Submissions
FOR EACH ROW
BEGIN
  DECLARE max_attempt INT;
  SELECT IFNULL(MAX(attempt_no),0) INTO max_attempt
  FROM Submissions
  WHERE user_id = NEW.user_id AND problem_id = NEW.problem_id;
  SET NEW.attempt_no = max_attempt + 1;
END$$
DELIMITER ;

-- AFTER INSERT: update Users counters (total_submissions and total_solved)
DELIMITER $$
CREATE TRIGGER trg_submissions_after_insert_user_counts
AFTER INSERT ON Submissions
FOR EACH ROW
BEGIN
  -- increment total_submissions
  UPDATE Users SET total_submissions = total_submissions + 1 WHERE user_id = NEW.user_id;

  -- if verdict is Accepted, increment total_solved (but only if this user hasn't solved this problem before)
  IF NEW.verdict = 'Accepted' THEN
    IF (SELECT COUNT(*) FROM Submissions WHERE user_id = NEW.user_id AND problem_id = NEW.problem_id AND verdict = 'Accepted') = 1 THEN
      UPDATE Users SET total_solved = total_solved + 1 WHERE user_id = NEW.user_id;
    END IF;
  END IF;
END$$
DELIMITER ;

-- AUDIT trigger for UPDATE (example)
DELIMITER $$
CREATE TRIGGER trg_submissions_update_audit
AFTER UPDATE ON Submissions
FOR EACH ROW
BEGIN
  INSERT INTO audit_log (table_name, op_type, row_id, details)
  VALUES ('Submissions','UPDATE', NEW.submission_id,
          JSON_OBJECT('old_verdict',OLD.verdict,'new_verdict',NEW.verdict,'user_id',NEW.user_id,'problem_id',NEW.problem_id));
END$$
DELIMITER ;

-- AUDIT trigger for DELETE
DELIMITER $$
CREATE TRIGGER trg_submissions_delete_audit
AFTER DELETE ON Submissions
FOR EACH ROW
BEGIN
  INSERT INTO audit_log (table_name, op_type, row_id, details)
  VALUES ('Submissions','DELETE', OLD.submission_id,
          JSON_OBJECT('user_id',OLD.user_id,'problem_id',OLD.problem_id,'verdict',OLD.verdict));
END$$
DELIMITER ;

-- =========================
-- 5. VIEWS
-- =========================

-- Leaderboard: users ordered by total_solved, then average acceptance time for accepted submissions
CREATE OR REPLACE VIEW vw_leaderboard AS
SELECT u.user_id, u.username, u.total_solved, u.total_submissions,
       AVG(CASE WHEN s.verdict='Accepted' THEN s.time_taken_ms END) AS avg_time_accepted_ms
FROM Users u
LEFT JOIN Submissions s ON u.user_id = s.user_id
GROUP BY u.user_id, u.username, u.total_solved, u.total_submissions
ORDER BY u.total_solved DESC, avg_time_accepted_ms ASC;

-- Tag summary view: problems per tag and accepted rate (global)
CREATE OR REPLACE VIEW vw_tag_summary AS
SELECT t.tag_id, t.tag_name,
       COUNT(DISTINCT pt.problem_id) AS problem_count,
       SUM(s.verdict='Accepted') AS total_accepted,
       COUNT(s.submission_id) AS total_submissions,
       CASE WHEN COUNT(s.submission_id)=0 THEN 0 ELSE ROUND(SUM(s.verdict='Accepted')/COUNT(s.submission_id),4) END AS accepted_rate
FROM Tags t
LEFT JOIN Problem_Tag pt ON t.tag_id = pt.tag_id
LEFT JOIN Problems p ON p.problem_id = pt.problem_id
LEFT JOIN Submissions s ON s.problem_id = p.problem_id
GROUP BY t.tag_id, t.tag_name;

-- User progress view: last submissions per user
CREATE OR REPLACE VIEW vw_user_last_submission AS
SELECT s.user_id, u.username, s.submission_id, s.problem_id, p.title, s.submission_date, s.verdict
FROM Submissions s
JOIN Users u ON s.user_id = u.user_id
JOIN Problems p ON s.problem_id = p.problem_id
WHERE (s.user_id, s.submission_date) IN (
  SELECT user_id, MAX(submission_date) FROM Submissions GROUP BY user_id
);

-- =========================
-- 6. STORED PROCEDURE (CURSOR)
--    Computes per-user per-tag attempts and accepted counts,
--    populates user_tag_stats (overwrites existing stats)
-- =========================

DELIMITER $$
CREATE PROCEDURE sp_compute_user_tag_stats()
BEGIN
  DECLARE done INT DEFAULT FALSE;
  DECLARE cur_user INT;
  DECLARE cur_tag INT;
  DECLARE u_cursor CURSOR FOR SELECT user_id FROM Users;
  DECLARE tag_cursor CURSOR FOR SELECT tag_id FROM Tags;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

  -- Clear existing
  TRUNCATE TABLE user_tag_stats;

  OPEN u_cursor;
  u_loop: LOOP
    SET done = FALSE;
    FETCH u_cursor INTO cur_user;
    IF done THEN LEAVE u_loop; END IF;

    -- for each tag
    OPEN tag_cursor;
    tag_loop: LOOP
      SET done = FALSE;
      FETCH tag_cursor INTO cur_tag;
      IF done THEN LEAVE tag_loop; END IF;

      -- compute attempts and accepted for cur_user,cur_tag
      INSERT INTO user_tag_stats (user_id, tag_id, attempts, accepted)
      SELECT
        cur_user,
        cur_tag,
        IFNULL(SUM(CASE WHEN st.user_id IS NOT NULL THEN 1 ELSE 0 END),0) as attempts,
        IFNULL(SUM(CASE WHEN st.verdict='Accepted' THEN 1 ELSE 0 END),0) as accepted
      FROM (
            SELECT s.submission_id, s.user_id, s.verdict, s.problem_id
            FROM Submissions s
            JOIN Problem_Tag pt ON s.problem_id = pt.problem_id
            WHERE s.user_id = cur_user AND pt.tag_id = cur_tag
           ) st;
    END LOOP tag_loop;
    CLOSE tag_cursor;
  END LOOP u_loop;
  CLOSE u_cursor;
END$$
DELIMITER ;

-- Run the SP once to populate user_tag_stats
CALL sp_compute_user_tag_stats();

-- =========================
-- 7. EXAMPLE QUERIES (joins, sets, subqueries, window functions)
--    I give you 20 useful SQL queries to demonstrate features.
-- =========================

-- 1) Basic join: get user submissions with problem and platform info
SELECT s.submission_id, u.username, p.title, pl.platform_name, s.verdict, s.submission_date
FROM Submissions s
JOIN Users u ON s.user_id = u.user_id
JOIN Problems p ON s.problem_id = p.problem_id
JOIN Platforms pl ON p.platform_id = pl.platform_id
ORDER BY s.submission_date DESC;

-- 2) Aggregation: top 5 problems by number of attempts
SELECT p.problem_id, p.title, COUNT(s.submission_id) AS attempts
FROM Problems p
LEFT JOIN Submissions s ON p.problem_id = s.problem_id
GROUP BY p.problem_id, p.title
ORDER BY attempts DESC
LIMIT 5;

-- 3) Window function: each user's last 3 submissions
SELECT user_id, submission_id, problem_id, verdict, submission_date,
       ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY submission_date DESC) rn
FROM Submissions
HAVING rn <= 3;

-- 4) Correlated subquery: users who solved a given problem (problem_id=1)
SELECT u.user_id, u.username
FROM Users u
WHERE EXISTS (SELECT 1 FROM Submissions s WHERE s.user_id = u.user_id AND s.problem_id = 1 AND s.verdict='Accepted');

-- 5) Set operation (UNION): problems that are Easy or Hard (unique list)
SELECT problem_id, title, difficulty FROM Problems WHERE difficulty = 'Easy'
UNION
SELECT problem_id, title, difficulty FROM Problems WHERE difficulty = 'Hard';

-- 6) Set difference emulation: problems not attempted by user_id=1
SELECT p.problem_id, p.title FROM Problems p
WHERE NOT EXISTS (
  SELECT 1 FROM Submissions s WHERE s.user_id = 1 AND s.problem_id = p.problem_id
);

-- 7) Tag-wise failure rate (per tag)
SELECT t.tag_name,
       SUM(s.verdict <> 'Accepted') AS failures,
       COUNT(s.submission_id) AS total,
       ROUND(SUM(s.verdict <> 'Accepted') / NULLIF(COUNT(s.submission_id),0),4) AS failure_rate
FROM Tags t
LEFT JOIN Problem_Tag pt ON t.tag_id = pt.tag_id
LEFT JOIN Submissions s ON s.problem_id = pt.problem_id
GROUP BY t.tag_name
ORDER BY failure_rate DESC;

-- 8) Leaderboard view usage
SELECT * FROM vw_leaderboard LIMIT 10;

-- 9) Platform comparison: acceptance rate per platform
SELECT pl.platform_name,
       SUM(s.verdict='Accepted') AS accepted,
       COUNT(s.submission_id) AS total_subs,
       ROUND(SUM(s.verdict='Accepted')/NULLIF(COUNT(s.submission_id),0),4) AS accept_rate
FROM Platforms pl
LEFT JOIN Problems p ON p.platform_id = pl.platform_id
LEFT JOIN Submissions s ON s.problem_id = p.problem_id
GROUP BY pl.platform_name
ORDER BY accept_rate DESC;

-- 10) Retrieve top 3 tags where user_id=1 has lowest accepted_rate (weak areas)
SELECT t.tag_name, uts.attempts, uts.accepted, uts.accepted_rate
FROM user_tag_stats uts
JOIN Tags t ON uts.tag_id = t.tag_id
WHERE uts.user_id = 1
ORDER BY uts.accepted_rate ASC
LIMIT 3;

-- 11) Find problems solved by all users (intersection-like)
SELECT p.problem_id, p.title
FROM Problems p
JOIN Submissions s ON p.problem_id = s.problem_id AND s.verdict='Accepted'
GROUP BY p.problem_id, p.title
HAVING COUNT(DISTINCT s.user_id) = (SELECT COUNT(*) FROM Users);

-- 12) Recent activity per platform (last 7 days)
SELECT pl.platform_name, COUNT(s.submission_id) AS submissions_last_7d
FROM Platforms pl
LEFT JOIN Problems p ON p.platform_id = pl.platform_id
LEFT JOIN Submissions s ON s.problem_id = p.problem_id AND s.submission_date >= NOW() - INTERVAL 7 DAY
GROUP BY pl.platform_name;

-- 13) Problems with multiple tags (for multi-discipline)
SELECT p.problem_id, p.title, COUNT(pt.tag_id) AS tag_count
FROM Problems p
JOIN Problem_Tag pt ON p.problem_id = pt.problem_id
GROUP BY p.problem_id, p.title
HAVING tag_count > 1;

-- 14) Users who never got Accepted
SELECT u.user_id, u.username FROM Users u
WHERE NOT EXISTS (SELECT 1 FROM Submissions s WHERE s.user_id = u.user_id AND s.verdict='Accepted');

-- 15) Pagination example: problems ordered by difficulty then title
SELECT problem_id, title, difficulty FROM Problems ORDER BY FIELD(difficulty,'Hard','Medium','Easy'), title LIMIT 0, 20;

-- 16) Using view vw_tag_summary
SELECT * FROM vw_tag_summary ORDER BY accepted_rate ASC;

-- 17) Show audit logs for last 50 changes
SELECT * FROM audit_log ORDER BY changed_at DESC LIMIT 50;

-- 18) Find avg attempts before accepted per problem
SELECT p.problem_id, p.title,
       AVG(attempts_before_accept) as avg_attempts_to_accept
FROM (
  SELECT problem_id, user_id, MIN(attempt_no) AS attempts_before_accept
  FROM Submissions
  WHERE verdict='Accepted'
  GROUP BY problem_id, user_id
) t
JOIN Problems p ON p.problem_id = t.problem_id
GROUP BY p.problem_id, p.title
ORDER BY avg_attempts_to_accept DESC;

-- 19) Example of a more complex analytic: weekly trend of submissions (last 8 weeks)
SELECT YEARWEEK(submission_date,1) as yw, COUNT(*) AS submissions
FROM Submissions
WHERE submission_date >= CURDATE() - INTERVAL 8 WEEK
GROUP BY yw
ORDER BY yw DESC;

-- 20) Query demonstrating a join + aggregate + having: users with average accepted time > 100 ms
SELECT u.user_id, u.username, AVG(s.time_taken_ms) AS avg_time
FROM Users u
JOIN Submissions s ON u.user_id = s.user_id AND s.verdict='Accepted'
GROUP BY u.user_id, u.username
HAVING avg_time > 100;

-- =========================
-- 8. USAGE NOTES & OPTIONALS
-- =========================
-- - To recompute tag stats: CALL sp_compute_user_tag_stats();
-- - To view leaderboard: SELECT * FROM vw_leaderboard;
-- - To add more sample data, insert into Problems, Problem_Tag, Tags, Submissions.
-- - To export: use mysqldump or MySQL Workbench export.

-- =========================
-- 9. EXTRA helpful utilities (stored functions / example view)
-- =========================

-- Function: get_user_accept_rate (returns acceptance rate for a user)
DROP FUNCTION IF EXISTS fn_user_accept_rate;
DELIMITER $$
CREATE FUNCTION fn_user_accept_rate(uid INT) RETURNS DECIMAL(6,4)
DETERMINISTIC
RETURN (
  SELECT ROUND(SUM(verdict='Accepted')/NULLIF(COUNT(*),0),4) FROM Submissions WHERE user_id = uid
);
$$
DELIMITER ;

-- Example: call function
-- SELECT fn_user_accept_rate(1) AS alice_accept_rate;

-- =========================
-- End of script
-- =========================

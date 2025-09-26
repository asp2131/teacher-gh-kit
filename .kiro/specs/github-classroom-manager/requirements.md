# Requirements Document

## Introduction

The GitHub Classroom Manager is a real-time web application built with Phoenix LiveView that enables JavaScript educators to efficiently manage and monitor student GitHub activity. The system provides live updates of student commit activity, GitHub Pages repository verification, and real-time classroom management capabilities without requiring page refreshes. The primary goal is to reduce manual GitHub checking from 30+ minutes to under 2 minutes per class while providing fault-tolerant background processing for GitHub API calls.

## Requirements

### Requirement 1

**User Story:** As a JavaScript educator, I want to authenticate with GitHub OAuth so that I can securely access student repository information and maintain persistent sessions.

#### Acceptance Criteria

1. WHEN an educator visits the application THEN the system SHALL display a GitHub OAuth login option
2. WHEN an educator clicks the GitHub OAuth login THEN the system SHALL redirect to GitHub's authorization page
3. WHEN GitHub authorization is successful THEN the system SHALL create a persistent LiveView session
4. WHEN the connection drops THEN the system SHALL automatically recover the session without requiring re-authentication
5. IF the educator is already authenticated THEN the system SHALL redirect directly to the dashboard

### Requirement 2

**User Story:** As a JavaScript educator, I want to create and manage classes so that I can organize my students by semester and term with live validation feedback.

#### Acceptance Criteria

1. WHEN an authenticated educator accesses the class creation form THEN the system SHALL provide live form validation
2. WHEN the educator enters a class name THEN the system SHALL validate the name in real-time and show feedback
3. WHEN the educator enters a semester/term THEN the system SHALL validate the term format and provide instant feedback
4. WHEN the educator submits a valid class form THEN the system SHALL create the class and provide real-time confirmation
5. WHEN the educator views their classes THEN the system SHALL display all classes with live status indicators

### Requirement 3

**User Story:** As a JavaScript educator, I want to import student GitHub usernames so that I can efficiently add multiple students to my class with live progress tracking.

#### Acceptance Criteria

1. WHEN the educator accesses the student import interface THEN the system SHALL provide a large text area with live parsing preview
2. WHEN the educator types usernames THEN the system SHALL validate usernames in real-time and show detected count
3. WHEN the educator submits the import THEN the system SHALL process usernames via background jobs with live progress updates
4. WHEN usernames are being processed THEN the system SHALL display real-time progress bars and validation results
5. IF a username is invalid THEN the system SHALL show specific error messages without blocking other imports
6. WHEN import is complete THEN the system SHALL display final results with success/failure counts

### Requirement 4

**User Story:** As a JavaScript educator, I want to verify students have GitHub Pages repositories so that I can ensure they've completed setup requirements with real-time status updates.

#### Acceptance Criteria

1. WHEN students are imported THEN the system SHALL automatically verify `<username>.github.io` repositories via background jobs
2. WHEN repository verification is in progress THEN the system SHALL show live status indicators
3. WHEN a repository exists THEN the system SHALL display ✅ status and generate live site links
4. WHEN a repository is missing THEN the system SHALL display ❌ status and provide creation guidance
5. IF a username is invalid THEN the system SHALL display ⚠️ status with specific error information
6. WHEN repository status changes THEN the system SHALL update the display in real-time without page refresh

### Requirement 5

**User Story:** As a JavaScript educator, I want to see live updates of student commit activity so that I can monitor their coding practice in real-time during class sessions.

#### Acceptance Criteria

1. WHEN the educator views the class dashboard THEN the system SHALL display student commit timestamps that update automatically
2. WHEN commit timestamps change THEN the system SHALL update "X minutes ago" displays every 2 minutes automatically
3. WHEN new commits are detected THEN the system SHALL refresh commit data via background jobs without blocking the UI
4. WHEN the system updates timestamps THEN the system SHALL show live indicators (⟳) for recently updated data
5. IF GitHub API calls fail THEN the system SHALL retry automatically without crashing the interface
6. WHEN the educator manually refreshes THEN the system SHALL immediately update all commit data

### Requirement 6

**User Story:** As a JavaScript educator, I want to view a 5-day commit calendar for each student so that I can monitor daily coding practice patterns with live updates.

#### Acceptance Criteria

1. WHEN the educator views the dashboard THEN the system SHALL display a 5-day commit calendar for each student
2. WHEN commits occur on a day THEN the system SHALL display ● (filled dot) for that day
3. WHEN no commits occur on a day THEN the system SHALL display ○ (empty dot) for that day
4. WHEN commit data refreshes THEN the system SHALL update calendar dots automatically
5. WHEN hovering over calendar dots THEN the system SHALL show commit count tooltips

### Requirement 7

**User Story:** As a JavaScript educator, I want to manage individual students so that I can add, remove, and sort students with instant UI updates.

#### Acceptance Criteria

1. WHEN the educator adds a student THEN the system SHALL provide live validation feedback and instant UI updates
2. WHEN the educator removes a student THEN the system SHALL update the UI immediately without page refresh
3. WHEN the educator sorts students THEN the system SHALL provide sorting by name or last commit time
4. WHEN student data changes THEN the system SHALL maintain sort order automatically
5. WHEN operations are in progress THEN the system SHALL show appropriate loading indicators

### Requirement 8

**User Story:** As a JavaScript educator, I want connection status indicators so that I know when I'm viewing live versus stale data.

#### Acceptance Criteria

1. WHEN the LiveView connection is active THEN the system SHALL display 🟢 live status indicators
2. WHEN the connection is lost THEN the system SHALL display connection status warnings
3. WHEN the connection is restored THEN the system SHALL automatically recover and update status indicators
4. WHEN data is being refreshed THEN the system SHALL show refresh indicators
5. IF the connection fails to recover THEN the system SHALL provide manual reconnection options

### Requirement 9

**User Story:** As a JavaScript educator, I want the system to handle concurrent usage so that multiple teachers can use the application simultaneously without performance degradation.

#### Acceptance Criteria

1. WHEN 50+ teachers use the system simultaneously THEN the system SHALL maintain response times under 2 seconds
2. WHEN background jobs are processing THEN the system SHALL handle 100+ students per minute without blocking the UI
3. WHEN multiple teachers import students THEN the system SHALL process imports independently without interference
4. WHEN system resources are under load THEN the system SHALL maintain live update functionality
5. IF system capacity is exceeded THEN the system SHALL gracefully degrade with appropriate user notifications

### Requirement 10

**User Story:** As a JavaScript educator, I want fault-tolerant background processing so that GitHub API issues don't disrupt my classroom management workflow.

#### Acceptance Criteria

1. WHEN GitHub API calls fail THEN the system SHALL retry automatically with exponential backoff
2. WHEN API rate limits are hit THEN the system SHALL queue requests and process them when limits reset
3. WHEN one student's data fails THEN the system SHALL continue processing other students without interruption
4. WHEN background jobs encounter errors THEN the system SHALL log errors and continue operation
5. IF persistent API issues occur THEN the system SHALL notify the educator while maintaining existing functionality
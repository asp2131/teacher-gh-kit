# GitHub Classroom Manager - Simplified Elixir/LiveView MVP PRD

## Executive Summary

A real-time web tool built with Phoenix LiveView that enables JavaScript educators to import student GitHub usernames, verify GitHub Pages repositories, and monitor commit activity with live timestamp updates and 5-day commit calendars that refresh automatically.

## Problem Statement

JavaScript teachers need a simple way to:
- Import and manage lists of student GitHub usernames
- Verify students have created their `<username>.github.io` repository
- See live updates of student coding activity without refreshing
- Monitor daily coding practice patterns in real-time

## MVP Goals

### Primary Goals
- Provide live updates of student commit activity without page refreshes
- Reduce manual GitHub checking from 30+ minutes to under 2 minutes per class
- Enable real-time monitoring during class sessions
- Deliver fault-tolerant background processing for GitHub API calls

### Success Metrics
- Live update latency: < 5 seconds for commit timestamp changes
- Time to check entire class of 35 students: < 2 minutes
- Setup time for new class: < 3 minutes
- Support 3 classes with 35 students each (105 total students per teacher)
- Concurrent user support: 50+ teachers simultaneously

## Core Features

### 1. Real-Time Authentication
- **GitHub OAuth with LiveView sessions** - Persistent connection management
- Access to public repository information
- Automatic session recovery on connection drops

### 2. Live Class Management
**Class Creation**
- Create class with name and semester/term
- Live form validation with instant feedback
- Real-time class creation confirmation

**Live Student Import**
- Large text area with live parsing preview
- Real-time username validation as you type
- Live progress tracking during bulk import
- Support both comma-separated and newline-separated formats
- Background job processing with live status updates

### 3. Real-Time GitHub Pages Verification
**Live Repository Checking**
- Background verification of `<username>.github.io` repositories
- Live status updates: ✅ Has Pages Repo, ❌ Missing Pages Repo, ⚠️ Invalid Username
- Real-time link generation to GitHub Pages sites

### 4. Live Dashboard
**Real-Time Class Overview**
- **PRIORITY: Live timestamp updates**: "5 minutes ago" → "6 minutes ago" automatically
- Student name (fetched from GitHub profile)
- GitHub Pages repository status
- **Automatic refresh** of commit timestamps every 2 minutes
- Basic 5-day commit calendar (updates with timestamp refreshes)
- Live connection indicators showing data freshness

**Live Operations**
- Add students with live validation feedback
- Remove students with instant UI updates
- Basic sorting by name or last commit time
- Real-time status indicators for timestamp updates

## Technical Architecture

### Tech Stack
- **Framework**: Phoenix 1.7 with LiveView
- **Language**: Elixir 1.15+
- **Database**: PostgreSQL with Ecto
- **Real-time**: Phoenix PubSub + LiveView WebSockets
- **Background Jobs**: Oban for GitHub API processing
- **GitHub API**: Custom client with Finch HTTP
- **Hosting**: Fly.io with single instance (MVP)

### Database Schema
```sql
users (
  id, github_id, github_username, 
  name, avatar_url, email, 
  inserted_at, updated_at
)

classes (
  id, teacher_id, name, term, 
  inserted_at, updated_at
)

class_students (
  id, class_id, student_github_username, 
  student_name, has_pages_repo, 
  pages_repo_url, live_site_url,
  last_commit_at, added_at, updated_at
)

commit_activities (
  id, class_id, student_username, 
  commit_date, commit_count,
  last_commit_at, updated_at
)

background_jobs (
  id, class_id, job_type, status, 
  progress, total, errors,
  inserted_at, updated_at
)
```

### LiveView Architecture
- **ClassLive** - Main dashboard with live student list
- **ImportLive** - Real-time student import with progress
- **StudentComponent** - Individual student cards with live updates
- **CommitCalendarComponent** - 5-day calendar with live commit dots

### Background Job Processing
- **ImportStudentsJob** - Validate usernames and fetch GitHub data
- **RefreshCommitsJob** - Update commit timestamps every 2 minutes
- **VerifyPagesReposJob** - Check GitHub Pages repository existence

## Real-Time User Experience

### Live Teacher Workflow
1. **Login** with GitHub OAuth (persistent LiveView connection)
2. **Create Class**: Live form validation, instant class creation
3. **Import Students**: Live progress bar and validation results
4. **Live Dashboard**: Automatic updates without refreshing

### Live Dashboard Experience
```
Class: JavaScript Fundamentals (Fall 2024)          🟢 Live Timestamps Active

Auto-refresh: ON (every 2 minutes)                           [Manual Refresh]

┌─────────────────┬──────────────┬─────────────────┬─────────────────┬──────────────┐
│ Student         │ Pages Repo   │ Last Commit     │ 5-Day Activity  │ Links        │
├─────────────────┼──────────────┼─────────────────┼─────────────────┼──────────────┤
│ Josh Smith      │ ✅ Active    │ 5 minutes ago ⟳ │ ●●○●○          │ [Repo][Site] │
│ Sarah Brown     │ ✅ Active    │ 2 hours ago     │ ●○●●○          │ [Repo][Site] │
│ Mike Jones      │ ❌ Missing   │ -               │ ○○○○○          │ [Create]     │
│ Lisa Wilson     │ ✅ Active    │ 3 days ago      │ ●○○●○          │ [Repo][Site] │
└─────────────────┴──────────────┴─────────────────┴─────────────────┴──────────────┘

Legend: ● = commits that day, ○ = no commits, ⟳ = timestamp just updated live
```

### Live Import Experience
```
Add Students to Class

Paste student GitHub usernames (comma or line separated):
┌─────────────────────────────────────────────────────────────┐
│ josh10318,JAICON504,akaibethley-spec,chrissybolton-skz     │
│ sarajbrown2027,paulcager9,ybgterrance                      │
│                                                             │
└─────────────────────────────────────────────────────────────┘

Live Preview: 7 usernames detected ✓

[Import Students]

Live Progress:
▓▓▓▓▓▓▓░░░ 70% (5/7 processed)

Live Results:
✅ josh10318 - Has Pages repo
✅ JAICON504 - Has Pages repo  
⚠️ akaibethley-spec - Valid user, missing Pages repo
🔄 Processing chrissybolton-skz...
```

## Phoenix LiveView Benefits

### Real-Time Features
- **Live Timestamps**: "5 minutes ago" updates to "6 minutes ago" automatically
- **Live Commit Calendar**: New commits appear as dots immediately
- **Live Import Progress**: Real-time progress bars and validation
- **Connection Recovery**: Automatic reconnection if internet drops

### Fault Tolerance
- **Background Jobs**: GitHub API failures don't crash the interface
- **Process Isolation**: One student's data issues don't affect others
- **Graceful Degradation**: UI remains responsive during API slowdowns
- **Automatic Retry**: Failed GitHub API calls retry automatically

### Concurrent Performance
- **Efficient Updates**: Only changed data refreshes, not entire page
- **Multi-User Support**: Multiple teachers can use simultaneously
- **Background Processing**: Non-blocking GitHub API operations
- **Resource Efficiency**: Lower server resources than traditional polling

## Development Timeline

### Week 1-2: LiveView Foundation
- Phoenix LiveView application setup
- GitHub OAuth with live session management
- Basic class creation with live validation
- Live student list display

### Week 3-4: Real-Time Features
- **PRIORITY: Live commit timestamp fetching and display**
- **Automatic timestamp updates** every 2 minutes via background jobs
- Real-time GitHub Pages verification
- Live student import with background job processing
- Background job system with Oban

### Week 5: Polish & Deploy
- 5-day commit calendar with live updates
- Connection status indicators
- Error handling and recovery
- Deploy to Fly.io with monitoring

## LiveView-Specific Advantages

### Real-Time Classroom Management
- **Live Monitoring**: Watch student activity during class sessions
- **Instant Feedback**: See commits appear as students work
- **No Refresh Needed**: Dashboard stays current automatically
- **Connection Awareness**: Know when you're seeing live vs stale data

### Technical Superiority
- **Efficient Updates**: Only timestamp changes get pushed, not full page
- **Fault Recovery**: Automatic reconnection and state restoration
- **Concurrent Handling**: 50+ teachers without performance degradation
- **Background Processing**: GitHub API calls don't block user interface

## Success Criteria

### Technical Performance
- Live update latency: < 5 seconds for commit changes
- Page load time: < 2 seconds initial render
- Concurrent users: 50+ simultaneous teachers
- Background job processing: 100+ students processed per minute

### User Experience
- Connection uptime: 99.5%+ for live features
- Auto-recovery: < 10 seconds to restore after connection loss
- Import speed: 35 students processed in < 75 seconds
- Live update accuracy: 99%+ of timestamp changes reflected

## Limitations & Future Enhancements

### MVP Limitations
- Single teacher per class
- No assignment tracking
- No email notifications
- No advanced analytics
- No data export

### Planned V2 Features
- Multi-teacher collaboration with live presence
- Real-time assignment tracking
- Live notifications for inactive students
- Advanced real-time analytics
- Live code review features

## Risk Mitigation

### Technical Risks
- **WebSocket Connection Issues**: Automatic reconnection with state recovery
- **GitHub API Rate Limits**: Background job queuing with retry logic
- **Database Connection Pooling**: Ecto handles connection management
- **Memory Usage**: Elixir's efficient process model

### Deployment Risks
- **Fly.io Learning Curve**: Comprehensive deployment documentation
- **Single Point of Failure**: Health checks and automatic restarts
- **Resource Monitoring**: Built-in LiveDashboard for system monitoring

## Competitive Advantages

### Real-Time Differentiation
- **Live Dashboard**: No other tool provides real-time commit monitoring
- **Fault Tolerance**: System continues working during partial failures
- **Efficient Scaling**: Handle more concurrent users with fewer resources
- **Live Collaboration**: Foundation for multi-teacher features

### Educational Focus
- **Classroom-Optimized**: Real-time monitoring perfect for live instruction
- **Instant Feedback**: Teachers see student work immediately
- **Connection Resilience**: Reliable during school network issues
- **Future-Proof**: Foundation for advanced collaborative features

## Open Source & Community

This tool will always remain completely free for educators. Future considerations:
- **Open source potential**: Consider releasing code to benefit the broader educational community
- **Community contributions**: Enable teachers and developers to contribute features and improvements
- **Educational partnerships**: Collaborate with coding bootcamps and schools for feedback and adoption

This simplified LiveView MVP delivers the core functionality with real-time superpowers, providing immediate value while building a foundation for advanced collaborative features as a permanently free educational resource.

## Monetization (Future)

### Free Tier (MVP)
- **3 classes maximum**
- **35 students per class**
- Basic live updates

### Pro Tier (V2)
- Unlimited classes and students
- Advanced real-time features
- Multi-teacher collaboration
- $15/month per teacher (premium for real-time value)

This simplified LiveView MVP delivers the core functionality with real-time superpowers, providing immediate value while building a foundation for advanced collaborative features.

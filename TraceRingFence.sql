USE [msdb]
GO

/****** Object:  Job [Trace RingFence]    Script Date: 04/07/2017 20:25:06 ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [[Uncategorized (Local)]]    Script Date: 04/07/2017 20:25:06 ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'Trace RingFence', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'No description available.', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Stop Rogue Traces]    Script Date: 04/07/2017 20:25:06 ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Stop Rogue Traces', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'--MaxRowsToCap. This will kill any trace that goes above that many rows. Pass a -1 value to ignore this
declare @MaxTraceRows int = -1
--MaxTimeCap. This will kill any traces that are run over a certain amount of time in minutes. Pass a -1 value to ignore this
declare @MaxTraceRunTimeMins int = 1
--UserWhiteList. This will store a list of users who will not be affected by this process and can therefore run any traces
declare @WhiteListUsers Table (UserName varchar(256))

--Insert as many users as you want here
Insert into @WhiteListUsers VALUES (''sa'')

	--Used to store the current trace to be killed
	DECLARE @trace int
	--cursor
    DECLARE trace_cursor CURSOR FOR   
		SELECT t.id
		FROM sys.traces t
		LEFT JOIN sys.dm_exec_sessions ses
			ON t.reader_spid = ses.session_id
		left JOIN @WhiteListUsers wlu
			on ses.login_name = wlu.UserName
		where ((t.event_count > @MaxTraceRows and @MaxTraceRows != -1) 
		OR (dateadd(minute,@MaxTraceRunTimeMins, t.start_time)) < GetDate() AND @MaxTraceRunTimeMins != -1)
		and wlu.UserName is null
		and t.status = 1
		and t.reader_spid is not null

    OPEN trace_cursor  
    FETCH NEXT FROM trace_cursor INTO @trace  
    WHILE @@FETCH_STATUS = 0  
    BEGIN  
		print @trace
		--stop the trace
		Exec sp_trace_setstatus @trace,0
		--loop
        FETCH NEXT FROM trace_cursor INTO @trace  
        END  
    CLOSE trace_cursor  
    DEALLOCATE trace_cursor 
', 
		@database_name=N'master', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Every Minute', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=4, 
		@freq_subday_interval=1, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20170704, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959, 
		@schedule_uid=N'6383acb1-8008-49af-8837-1a6996f6ba27'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:

GO



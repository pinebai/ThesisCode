program JetPanels

use NumberKindsModule
use SphereGeomModule
use OutputWriterModule
use LoggerModule
use ParticlesEdgesPanelsModule
use PanelVelocityParallelModule
use TracerAndVorticityDistributionModule
use RefineRemeshModule

implicit none

include 'mpif.h'

! Grid Variables
type(Particles), pointer :: gridParticles=>null()
type(Edges), pointer :: gridEdges=>null()
type(Panels), pointer :: gridPanels=>null()
integer(kint) :: panelKind, initNest, AMR, nTracer, remeshInterval
integer(kint), parameter :: problemKind = BVE_SOLVER
logical(klog) :: remeshFlag
integer(kint), parameter :: problemID = JET
integer(kint) :: useRelativeTol, maxRefine
real(kreal) :: amrTol1, amrTol2, newOmega
real(kreal) :: circTol, varTol, maxCirc, baseVar, maxx0(3), minx0(3)

! Jet test case variables
integer(kint) :: perturbWaveNum
real(kreal) :: beta, lat0, perturbAmp

! Error calculation variables
real(kreal), allocatable :: totalKineticEnergy(:), totalEnstrophy(:)

! Logger & Computation management variables
type(Logger) :: exeLog
integer(kint) :: logOut = 6
character(len=28) :: logKey
character(len=128) :: logString
real(kreal) :: wtime, etime, etime0,  percentDone
logical(klog) :: newEst
integer(kint), parameter :: REAL_INIT_BUFFER_SIZE = 8, INT_INIT_BUFFER_SIZE = 7
integer(kint) :: procRank, numProcs, mpiErrCode, intBuffer(INT_INIT_BUFFER_SIZE)
real(kreal) :: realBuffer(REAL_INIT_BUFFER_SIZE)

! Timestepping variables
real(kreal) :: t, dt, tfinal
integer(kint) :: timeJ, timesteps

! I/O & User variables
character(len=128) :: jobPrefix, outputDir
character(len=256) :: vtkRoot, vtkFile, dataFile
character(len=48) :: amrString
integer(kint), parameter :: readUnit = 12, writeUnit = 13
integer(kint) :: readStat, writeStat, frameOut, frameCounter
namelist /gridInit/ panelKind, initnest, AMR, remeshInterval, amrTol1, amrTol2, useRelativeTol, newOmega, maxRefine
namelist /time/ dt, tfinal
namelist /fileIO/ jobPrefix, outputDir, frameOut
namelist /jetInit/ lat0, beta, perturbAmp, perturbWaveNum

! General variables
integer(kint) :: j, k

!~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!
!	Part 1 : Initialize the computing environment / get user input  !
!~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!

call MPI_INIT(mpiErrCode)
call MPI_COMM_SIZE(MPI_COMM_WORLD,numProcs,mpiErrCode)
call MPI_COMM_RANK(MPI_COMM_WORLD,procRank,mpiErrCode)
call New(exeLog,DEBUG_LOGGING_LEVEL,logOut)
write(logKey,'(A,I0.2,A)') 'EXE_LOG_',procRank,' : '
if ( procRank == 0) then
	call LogMessage(exeLog,TRACE_LOGGING_LEVEL,logKey,"*** Program START ***")
	call LogMessage(exeLog,DEBUG_LOGGING_LEVEL,logKey//" numProcs = ",numProcs)
	! Read user input from namelist file
	open(unit=readUnit,file='JetPanels.namelist',action='READ',status='OLD',iostat=readStat)
		if (readstat /= 0 ) then
			call LogMessage(exeLog,ERROR_LOGGING_LEVEL,logKey," ERROR opening namelist file.")
			stop
		endif
		read(readunit,nml=gridinit)
		rewind(readunit)
		read(readunit,nml=time)
		rewind(readunit)
		read(readunit,nml=fileIO)
		rewind(readunit)
		read(readunit,nml=jetInit)
	close(readunit)

	intBuffer(1) = panelKind
	intBuffer(2) = initNest
	intBuffer(3) = AMR
	intBuffer(4) = remeshInterval
	intBuffer(5) = perturbWaveNum
	intBuffer(6) = useRelativeTol
	intBuffer(7) = maxRefine

	realBuffer(1) = amrTol1
	realBuffer(2) = amrTol2
	realBuffer(3) = dt
	realBuffer(4) = tfinal
	realBuffer(5) = beta
	realBuffer(6) = lat0
	realBuffer(7) = perturbAmp
	realBuffer(8) = newOmega
endif

call MPI_BCAST(intBuffer,INT_INIT_BUFFER_SIZE,MPI_INTEGER,0,MPI_COMM_WORLD,mpiErrCode)
call MPI_BCAST(realBuffer,REAL_INIT_BUFFER_SIZE,MPI_DOUBLE_PRECISION,0,MPI_COMM_WORLD,mpiErrCode)

panelKind = intBuffer(1)
initNest = intBuffer(2)
AMR = intBuffer(3)
remeshInterval = intBuffer(4)
perturbWaveNum = intBuffer(5)
useRelativeTol = intBuffer(6)
maxRefine = intBuffer(7)

amrTol1 = realBuffer(1)
amrTol2 = realBuffer(2)
dt = realBuffer(3)
tfinal = realBuffer(4)
beta = realBuffer(5)
lat0 = realBuffer(6)
perturbAmp = realBuffer(7)
newOmega = realBuffer(8)

!~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!
!	Part 2 : Initialize the grid		             !
!~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!

call SetOmega(newOmega)

! Init time stepping variables
t = 0.0_kreal
timeJ = 0
timesteps = floor(tfinal/dt)

allocate(totalKineticEnergy(0:timesteps))
totalKineticEnergy = 0.0_kreal
allocate(totalEnstrophy(0:timesteps))
totalEnstrophy = 0.0_kreal

nTracer = 3
call New(gridParticles,gridEdges,gridPanels,panelKind,initNest,AMR,nTracer,problemKind)
!call LogMessage(exeLog,DEBUG_LOGGING_LEVEL,trim(logkey)//'0 gaussConst = ',gaussConst)
call InitJet(gridParticles,gridPanels,lat0,beta,perturbAmp,perturbWaveNum)
!call LogMessage(exeLog,DEBUG_LOGGING_LEVEL,trim(logkey)//'1 gaussConst = ',gaussConst)
if ( AMR > 0 ) then
	call SetMaxRefinementLimit(maxRefine)
	maxCirc = maxval(abs(gridPanels%relVort(1:gridPanels%N))*gridPanels%area(1:gridPanels%N))
	baseVar = 0.0_kreal
	do j=1,gridPanels%N
		if ( .NOT. gridPanels%hasChildren(j) ) then
			maxx0 = gridPanels%x0(:,j)
			minx0 = gridPanels%x0(:,j)
			do k=1,panelKind
				if ( gridParticles%x0(1,gridPanels%vertices(k,j)) > maxx0(1) ) then
					maxx0(1) = gridParticles%x0(1,gridPanels%vertices(k,j))
				endif
				if ( gridParticles%x0(1,gridPanels%vertices(k,j)) < minx0(1) ) then
					minx0(1) = gridParticles%x0(1,gridPanels%vertices(k,j))
				endif
				if ( gridParticles%x0(2,gridPanels%vertices(k,j)) > maxx0(2) ) then
					maxx0(2) = gridParticles%x0(2,gridPanels%vertices(k,j))
				endif
				if ( gridParticles%x0(2,gridPanels%vertices(k,j)) < minx0(2) ) then
					minx0(2) = gridParticles%x0(2,gridPanels%vertices(k,j))
				endif
				if ( gridParticles%x0(3,gridPanels%vertices(k,j)) > maxx0(3) ) then
					maxx0(3) = gridParticles%x0(3,gridPanels%vertices(k,j))
				endif
				if ( gridParticles%x0(3,gridPanels%vertices(k,j)) < minx0(3) ) then
					minx0(3) = gridParticles%x0(3,gridPanels%vertices(k,j))
				endif
			enddo
			if ( sum(maxx0 - minx0) > baseVar ) baseVar = sum(maxx0 - minx0)
		endif
	enddo

	circTol = amrTol1 * maxCirc
	varTol = amrTol2 * baseVar
	if ( procRank == 0 ) then
		call LogMessage(exeLog,TRACE_LOGGING_LEVEL,trim(logKey)//' circTol = ',circTol)
		call LogMessage(exeLog,TRACE_LOGGING_LEVEL,trim(logKey)//' varTol = ',varTol)
		call LogMessage(exeLog,TRACE_LOGGING_LEVEL,trim(logKey)//' maxNest will be ',initNest+MAX_REFINEMENT+1)
		write(amrString,'(A,I1,A,I0.2,A)') 'AMR_',initNest,'to',initNest+MAX_REFINEMENT+1,'_'
	endif

	call InitRefine(gridParticles,gridEdges,gridPanels,circTol,varTol, problemID,&
		lat0,beta,perturbAmp,perturbWaveNum,procRank=procRank)

	call InitJet(gridParticles,gridPanels,lat0,beta,perturbAmp,perturbWaveNum)
else
	write(amrString,'(A,I1)') 'nest',initNest
endif


!
! Store initial latitude in tracer 1
!
do j=1,gridParticles%N
	gridParticles%tracer(j,1) = Latitude(gridParticles%x0(:,j))
enddo
do j=1,gridPanels%N
	if ( .NOT. gridPanels%hasChildren(j) )  then
		gridpanels%tracer(j,1) = Latitude(gridPanels%x0(:,j))
	endif
enddo
!
! Tracer 2 used for kinetic energy
!
! Store initial longitude in tracer 3
!
do j=1,gridParticles%N
	gridParticles%tracer(j,3) = Longitude(gridParticles%x0(:,j))
enddo
do j=1,gridPanels%N
	if (.NOT. gridPanels%hasChildren(j)) then
		gridPanels%tracer(j,3) = Longitude(gridPanels%x0(:,j))
	endif
enddo

totalEnstrophy(0) = 0.5_kreal*sum(gridPanels%area(1:gridpanels%N)*&
					gridPanels%relVort(1:gridPanels%N)*gridPanels%relVort(1:gridPanels%N))


frameCounter = 0
if (procRank == 0) then
	call PrintStats(gridParticles)
	call PrintStats(gridEdges)
	call PrintStats(gridPanels)

	! prepare output files
	if ( panelKind == 3) then
		write(dataFile,'(A,A,A,A,A,F4.2,A,F6.4,A)') trim(outputDir),trim(jobPrefix),'_tri',trim(amrString),'_rev',tfinal,'_dt',dt,'_'
	elseif (panelKind == 4) then
		write(dataFile,'(A,A,A,A,A,F4.2,A,F6.4,A)') trim(outputDir),trim(jobPrefix),'_quad',trim(amrString),'_rev',tfinal,'_dt',dt,'_'
	endif
	write(vtkRoot,'(A,A,A)') trim(outputDir),'vtkOut/',trim(jobPrefix)
	write(vtkFile,'(A,I0.4,A)') trim(vtkRoot),frameCounter,'.vtk'
	write(dataFile,'(A,A)')trim(dataFile),'.dat'
	wtime = MPI_WTIME()
	etime0 = MPI_WTIME()

	call vtkOutput(gridParticles,gridPanels,vtkFile)
endif

!~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!
!	Part 3 : Run the problem								    !
!~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!
call MPI_BARRIER(MPI_COMM_WORLD,mpiErrCode)
if (procRank == 0) call LogMessage(exeLog,DEBUG_LOGGING_LEVEL,logKey,'Setup complete. Starting time integration.')

call InitializeMPIRK4(gridParticles,gridPanels,procRank,numProcs)

remeshFlag = .False.
newEst = .False.
do timeJ = 0,timesteps-1
	! Remesh if necessary
	if ( mod(timeJ+1,remeshInterval) == 0 ) then
		remeshFlag = .True.
		if ( procRank == 0 ) &
		call LogMessage(exeLog,TRACE_LOGGING_LEVEL,logKey," Remesh triggered by remeshInterval.")
	endif
	if ( remeshFlag ) then

		call AdaptiveRemesh( gridParticles,gridEdges,gridPanels,&
								initNest, AMR, circTol, varTol, &
								procRank, problemID, &
								lat0, beta, perturbAmp, perturbWaveNum)

		remeshFlag = .False.
		call ResetRK4()
		do j=1,gridParticles%N
			gridParticles%tracer(j,1) = Latitude(gridParticles%x0(:,j))
		enddo
		do j=1,gridPanels%N
			if ( .NOT. gridPanels%hasChildren(j) )  then
				gridpanels%tracer(j,1) = Latitude(gridPanels%x0(:,j))
			endif
		enddo
		do j=1,gridParticles%N
			gridParticles%tracer(j,3) = Longitude(gridParticles%x0(:,j))
		enddo
		do j=1,gridPanels%N
			if (.NOT. gridPanels%hasChildren(j)) then
				gridPanels%tracer(j,3) = Longitude(gridPanels%x0(:,j))
			endif
		enddo
		if ( procRank == 0 ) then
			call PrintStats(gridParticles)
			call PrintStats(gridEdges)
			call PrintStats(gridPanels)
		endif
!		if ( abs(sum(gridPanels%relVort(1:gridPanels%N)*gridPanels%area(1:gridPanels%N))) > 0.1_kreal) then
!			call LogMessage(exeLog,WARNING_LOGGING_LEVEL,logKey,"Vorticity integral tolerance exceeded-- exiting.")
!			exit
!		endif
		newEst = .TRUE.
	endif

	!if ( procRank == 0 .AND. newEst ) etime = MPI_WTIME()

	! Advance time
	call BVERK4(gridParticles,gridPanels,dt,procRank,numProcs)
	t = real(timeJ+1,kreal)*dt

	totalKineticEnergy(timeJ+1) = totalKE
	totalEnstrophy(timeJ+1) = 0.5_kreal*sum(gridPanels%area(1:gridPanels%N)*&
			gridPanels%relVort(1:gridPanels%N)*gridPanels%relVort(1:gridPanels%N))
	if ( procRank == 0 ) then
		if ( ( timeJ == 1) .OR. ( newEst) ) then
			etime = MPI_WTIME() - etime0
			write(logString,'(A,F9.3,A)') 'Elapsed time = ', etime/60.0_kreal, ' minutes.'
			call LogMessage(exeLog,TRACE_LOGGING_LEVEL,logkey,logstring)
			write(logString,'(A,F9.3,A)') 'Estimated time left = ',etime/(60.0_kreal*real(timeJ,kreal))*real(timesteps-timeJ),' minutes.'
			call LogMessage(exeLog,TRACE_LOGGING_LEVEL,logKey,logString)
			newEst = .False.
		endif

		call LogMessage(exeLog,DEBUG_LOGGING_LEVEL,trim(logKey)//" t = ",t)

		if ( mod(timeJ+1,frameOut) == 0 ) then
			frameCounter = frameCounter + 1
			write(vtkFile,'(A,I0.4,A)') trim(vtkRoot),frameCounter,'.vtk'
			call vtkOutput(gridParticles,gridPanels,vtkFile)
		endif

	endif
enddo

!~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!
!	Part 4 : Finish and clear memory
!~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!

if ( procRank == 0 ) then
	open(unit=writeUnit,file=dataFile,status='REPLACE',action='WRITE',iostat=writeStat)
	if ( writeStat /= 0 ) call LogMessage(exeLog,ERROR_LOGGING_LEVEL,logkey,'ERROR opening dataFile.')
		write(writeUnit,'(5A24)') 'totalKE','totalEnstrophy','relVort l1','relVort l2','relVort linf'
		do j=0,timesteps
			write(writeUnit,'(2F24.15)') totalKineticEnergy(j), totalEnstrophy(j)
		enddo
	close(writeUnit)

	wTime = MPI_WTIME() - wtime
	call LogMessage(exeLog,TRACE_LOGGING_LEVEL,logKey,"*** Program END ***")
	call LogMessage(exeLog,TRACE_LOGGING_LEVEL,trim(logKey)//' data file = ',trim(dataFile))
	write(vtkFile,'(A,A)') trim(vtkRoot),'XXXX.vtk'
	call LogMessage(exeLog,TRACE_LOGGING_LEVEL,trim(logKey)//' vtkFiles = ',trim(vtkFile))
	call LogMessage(exeLog,TRACE_LOGGING_LEVEL,logKey,'Tracer1 = initial latitude.')
	call LogMessage(exeLog,TRACE_LOGGING_LEVEL,logKey,'Tracer2 = kinetic energy.')
	if ( AMR > 0 ) then
		if ( useRelativeTOl > 0 ) call LogMessage(exeLog,TRACE_LOGGING_LEVEL,logKey,"AMR used relative tolerances.")
		call LogMessage(exeLog,TRACE_LOGGING_LEVEL,logKey//'panelKind = ',panelKind)
		call LogMessage(exeLog,TRACE_LOGGING_LEVEL,logkey//'initNest = ',initNest)
		call LogMessage(exeLog,TRACE_LOGGING_LEVEL,logKey//'circTol = ',circTol)
		call LogMessage(exeLog,TRACE_LOGGING_LEVEL,logkey//'varTol = ',varTol)
	endif
	write(logString,'(A,F9.2,A)') " elapsed time = ",wtime/60.0_kreal," minutes."
	call LogMessage(exeLog,TRACE_LOGGING_LEVEL,logKey,trim(logString))


endif

deallocate(totalKineticEnergy)
deallocate(totalEnstrophy)
call FinalizeMPIRK4()
call Delete(gridParticles,gridEdges,gridPanels)
call Delete(exeLog)

call MPI_FINALIZE(mpiErrCode)


end program

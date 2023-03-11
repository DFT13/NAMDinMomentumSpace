module shop
  use prec
  use fileio
  use hamil
  use couplings
  implicit none

  contains

  ! calculate surface hopping probabilities
  subroutine runSH(ks, inp, olap)
    implicit none

    type(TDKS), intent(inout) :: ks
    type(namdInfo), intent(in) :: inp
    type(overlap), intent(in) :: olap
    integer :: i, j, ibas, nbas, tion, Nt, iq
    integer, allocatable :: cstat_all(:,:), occb(:,:), occbtot(:)
    integer :: cstat, nstat

    ks%sh_pops = 0
    ks%sh_prop = 0
    nbas = ks%ndim
    Nt = inp%NAMDTIME / inp%POTIM

    allocate(cstat_all(inp%NTRAJ, inp%NINIBS))
    allocate(occb(inp%NTRAJ, inp%NBASIS))
    allocate(occbtot(inp%NBASIS))
    ! tag of basis occupied

    occb = 0; occbtot = 0
    do i=1, inp%NINIBS
      ibas = inp%BASSEL(inp%INIKPT(i), inp%INIBAND(i))
      cstat_all(:,i) = ibas
      occb(:,ibas) = 1
      occbtot(ibas) = 1
    end do

    ! initialize the random seed for ramdom number production
    call init_random_seed()

    if (inp%LEPC) then

      ! ks%ph_pops = 0
      ! ks%ph_prop = 0
      call calcBftot(ks, inp)

      do tion=1, Nt

        do ibas=1,nbas
          if (occbtot(ibas)==0) cycle
          call calcprop_EPC(tion, ibas, ks, inp, olap)
        end do

        do i=1, inp%NTRAJ
          do j=1, inp%NINIBS

            cstat = cstat_all(i,j)
            call whichToHop(cstat, nstat, ks)

            if (nstat /= cstat .AND. occb(i,nstat)>0) cycle
            occb(i,cstat) = 0; occb(i,nstat) = 1
            occbtot(cstat) = 0; occbtot(nstat) = 1
            ks%sh_pops(nstat, tion) = ks%sh_pops(nstat, tion) + 1
            cstat_all(i,j) = nstat

            if (nstat == cstat) cycle
            iq = olap%kkqmap(cstat, nstat)
            if (iq>0) then
              ks%ph_pops(iq, :, tion) &
                = ks%ph_pops(iq, :, tion) &
                + SUM(ks%ph_prop(cstat,nstat,:,:), dim=2)
            end if

          end do
        end do

      end do
      ks%sh_pops = ks%sh_pops / inp%NTRAJ
      ! ks%ph_pops = ks%ph_pops / inp%NTRAJ

    else

      do tion=1, Nt

        do ibas=1,nbas
          if (occbtot(ibas)==0) cycle
          call calcprop(tion, ibas, ks, inp)
        end do

        do i=1, inp%NTRAJ
          do j=1, inp%NINIBS
            cstat = cstat_all(i,j)
            call whichToHop(cstat, nstat, ks)
            if (nstat /= cstat .AND. occb(i,nstat)>0) cycle
            occb(i,cstat) = 0; occbtot(cstat) = 0
            occb(i,nstat) = 1; occbtot(nstat) = 1
            ks%sh_pops(nstat, tion) = ks%sh_pops(nstat, tion) + 1
            cstat_all(i,j) = nstat
          end do
        end do

      end do
      ks%sh_pops = ks%sh_pops / inp%NTRAJ

    end if

  end subroutine


  ! initialize the random seed from the system clock
  ! code from: http://fortranwiki.org/fortran/show/random_seed
  subroutine init_random_seed()
    implicit none
    integer :: i, n, clock
    integer, dimension(:), allocatable :: seed

    call random_seed(size = n)
    allocate(seed(n))

    call system_clock(count=clock)

    seed = clock + 37 * (/ (i - 1, i = 1, n) /)
    call random_seed(put = seed)

    deallocate(seed)
  end subroutine

  subroutine whichToHop(cstat, nstat, ks)
    implicit none

    integer, intent(in) :: cstat
    integer, intent(inout) :: nstat
    type(TDKS), intent(in) :: ks

    integer :: i
    real(kind=q) :: lower, upper, r

    call random_number(r)

    nstat = cstat
    do i=1, ks%ndim
      if (i == 1) then
        lower = 0
        upper = ks%sh_prop(cstat,i)
      else
        lower = upper
        upper = upper + ks%sh_prop(cstat,i)
      end if
      if (lower <= r .AND. r < upper) then
        nstat = i
        exit
      end if
    end do

  end subroutine

  subroutine calcprop(tion, cstat, ks, inp)
    implicit none

    type(TDKS), intent(inout) :: ks
    type(namdInfo), intent(in) :: inp
    integer, intent(in) :: tion
    integer, intent(in) :: cstat

    integer :: i, j
    real(kind=q) :: Akk

    Akk = CONJG(ks%psi_a(cstat, tion)) * ks%psi_a(cstat, tion)

    ks%Bkm = 2. * REAL(CONJG(ks%psi_a(cstat, tion)) * ks%psi_a(:, tion) * &
                  ks%NAcoup(cstat, :, tion))
    call calcBfactor(ks, inp, cstat, tion)

    ks%sh_prop(cstat,:) = ks%Bkm / Akk * inp%POTIM * ks%sh_Bfactor(cstat,:)
    forall (i=1:ks%ndim, ks%sh_prop(cstat,i) < 0) ks%sh_prop(cstat,i) = 0

  end subroutine

  subroutine calcprop_EPC(tion, cstat, ks, inp, olap)
    implicit none

    type(TDKS), intent(inout) :: ks
    type(namdInfo), intent(in) :: inp
    integer, intent(in) :: tion
    integer, intent(in) :: cstat
    type(overlap), intent(in) :: olap

    real(kind=q) :: Akk, norm
    complex(kind=q), allocatable :: epcoup(:) ! , eptemp(:,:)
    integer :: i, iq

    allocate(epcoup(ks%ndim))
    ! allocate(epcoup(ks%ndim), eptemp(inp%NMODES, 2))
    do i=1,ks%ndim
      iq = olap%kkqmap(cstat, i)
      epcoup(i) = SUM(olap%EPcoup(cstat,i,:,:,1) * (ks%PhQ(iq,:,:,tion) ** 2))
      ! eptemp = olap%EPcoup(cstat,i,:,:,1) * ks%PhQ(iq,:,:,tion)
      ! ks%ph_prop(cstat, i, :, :) = ABS(eptemp) ** 2
      ! norm = SUM(ks%ph_prop(cstat, i, :, :))
      ! if (norm>0) ks%ph_prop(cstat, i, :, :) = ks%ph_prop(cstat, i, :, :) / norm
    end do

    Akk = CONJG(ks%psi_a(cstat, tion)) * ks%psi_a(cstat, tion)
    ks%Bkm = -2. / hbar * AIMAG( CONJG(ks%psi_a(cstat, tion)) * &
             ks%psi_a(:, tion) * epcoup(:) )

    ks%sh_prop(cstat,:) = ks%Bkm / Akk * inp%POTIM * ks%sh_Bfactor(cstat,:)
    forall (i=1:ks%ndim, ks%sh_prop(cstat,i) < 0) ks%sh_prop(cstat,i) = 0

  end subroutine

  ! Calculate Boltzmann factors for SH probability correction.
  subroutine calcBfactor(ks, inp, cstat, tion)
    implicit none
    type(TDKS), intent(inout) :: ks
    type(namdInfo), intent(in) :: inp
    integer, intent(in) :: tion
    integer, intent(in) :: cstat

    integer :: jb, nb
    real(kind=q) :: dE, kbT

    nb = ks%ndim
    kbT = inp%TEMP * BOLKEV
    ks%sh_Bfactor(cstat,:) = 1.0_q

    if (inp%LHOLE) then
      do jb=1, nb
        dE = ks%eigKs(jb, tion) - ks%eigKs(cstat,tion)
        if (dE<0) then
          ks%sh_Bfactor(cstat,jb) = exp(dE / kbT)
        end if
      end do
    else
      do jb=1, nb
        dE = ks%eigKs(jb,tion) - ks%eigKs(cstat, tion)
        if (dE>0) then
          ks%sh_Bfactor(cstat,jb) = exp(-dE / kbT)
        end if
      end do
    end if

  end subroutine

  subroutine calcBftot(ks, inp)
    ! Calculate total Boltzmann factors only once
    ! if ks eigs are invariable.
    implicit none
    type(TDKS), intent(inout) :: ks
    type(namdInfo), intent(in) :: inp

    integer :: ib, nb

    nb = ks%ndim
    do ib=1, nb
      call calcBfactor(ks, inp, ib, 1)
    end do
  end subroutine

  ! need a subroutine here to write the results we need
  subroutine printSH(ks, inp)
    implicit none
    type(TDKS), intent(in) :: ks
    type(namdInfo), intent(in) :: inp

    integer :: i, j, tion, Nt, ierr, io
    character(len=48) :: buf

    write(buf, *) inp%NAMDTINI
    open(unit=24, file='SHPROP.' // trim(adjustl(buf)), &
         status='unknown', action='write', iostat=ierr)
    open(unit=25, file='PSICT.' // trim(adjustl(buf)), &
         status='unknown', action='write', iostat=ierr)
    if (ierr /= 0) then
      write(*,*) "SHPROP file I/O error!"
      stop
    end if

    if (.NOT. inp%LEPC) then

      do io = 24, 25
        write(io,'(A,A12,A3,I5)') '#', 'BMIN',     ' = ', inp%BMIN
        write(io,'(A,A12,A3,I5)') '#', 'BMAX',     ' = ', inp%BMAX
        ! write(io,'(A,A12,A3,I5)') '#', 'INIBAND',  ' = ', inp%INIBAND
        write(io,'(A,A12,A3,I5)') '#', 'NBANDS',   ' = ', inp%NBANDS

        write(io,'(A,A12,A3,I5)')   '#', 'NSW',    ' = ', inp%NSW
        write(io,'(A,A12,A3,F5.1)') '#', 'POTIM',  ' = ', inp%POTIM
        write(io,'(A,A12,A3,F5.1)') '#', 'TEMP',   ' = ', inp%TEMP

        write(io,'(A,A12,A3,I5)') '#', 'NAMDTINI', ' = ', inp%NAMDTINI
        write(io,'(A,A12,A3,I5)') '#', 'NAMDTIME', ' = ', inp%NAMDTIME
        write(io,'(A,A12,A3,I5)') '#', 'NTRAJ',    ' = ', inp%NTRAJ
        write(io,'(A,A12,A3,I5)') '#', 'NELM',     ' = ', inp%NELM

        write(io,'(A,A12,A3,A)')  '#', 'RUNDIR',   ' = ', TRIM(ADJUSTL(inp%rundir))
        write(io,'(A,A12,A3,L5)') '#', 'LHOLE',    ' = ', inp%LHOLE
        write(io,'(A,A12,A3,L5)') '#', 'LSHP',     ' = ', inp%LSHP
        write(io,'(A,A12,A3,L5)') '#', 'LCPTXT',   ' = ', inp%LCPTXT
        write(io,'(A,A12,A3,L5)') '#', 'LGAMMA',   ' = ', inp%LGAMMA
      end do

    else

      do io = 24, 25
        write(io,'(A,A12,A3,I6)')     '#', 'BMIN',     ' = ', inp%BMIN
        write(io,'(A,A12,A3,I6)')     '#', 'BMAX',     ' = ', inp%BMAX
        write(io,'(A,A12,A3,I6)')     '#', 'KMIN',     ' = ', inp%KMIN
        write(io,'(A,A12,A3,I6)')     '#', 'KMAX',     ' = ', inp%KMAX
        if (inp%EMIN > -1.0E5_q) &
          write(io,'(A,A12,A3,F6.2)') '#', 'EMIN',     ' = ', inp%EMIN
        if (inp%EMAX <  1.0E5_q) &
          write(io,'(A,A12,A3,F6.2)') '#', 'EMAX',     ' = ', inp%EMAX

        write(io,'(A,A12,A3,I6)')     '#', 'NBASIS',   ' = ', inp%NBASIS
        write(io,'(A,A12,A3,I6)')     '#', 'NBANDS',   ' = ', inp%NBANDS
        write(io,'(A,A12,A3,I6)')     '#', 'NKPOINTS', ' = ', inp%NKPOINTS
        ! write(io,'(A,A12,A3,I6)')     '#', 'INIBAND',  ' = ', inp%INIBAND
        ! write(io,'(A,A12,A3,I6)')     '#', 'INIKPT',   ' = ', inp%INIKPT

        write(io,'(A,A12,A3,I6)')     '#', 'NSW',      ' = ', inp%NSW
        write(io,'(A,A12,A3,F6.1)')   '#', 'POTIM',    ' = ', inp%POTIM
        write(io,'(A,A12,A3,F6.1)')   '#', 'TEMP',     ' = ', inp%TEMP
        write(io,'(A,A12,A3,I6)')     '#', 'NAMDTINI', ' = ', inp%NAMDTINI
        write(io,'(A,A12,A3,I6)')     '#', 'NAMDTIME', ' = ', inp%NAMDTIME
        write(io,'(A,A12,A3,I6)')     '#', 'NTRAJ',    ' = ', inp%NTRAJ
        write(io,'(A,A12,A3,I6)')     '#', 'NELM',     ' = ', inp%NELM

        write(io,'(A,A12,A3,L6)')     '#', 'LEPC',     ' = ', inp%LEPC
        write(io,'(A,A12,A3,L6)')     '#', 'LARGEBS',  ' = ', inp%LARGEBS
        write(io,'(A,A12,A3,I6)')     '#', 'EPCTYPE',  ' = ', inp%EPCTYPE
        write(io,'(A,A12,A3,L6)')     '#', 'LBASSEL',  ' = ', inp%LBASSEL
        write(io,'(A,A12,A3,L6)')     '#', 'LSORT',    ' = ', inp%LSORT
        write(io,'(A,A12,A3,L6)')     '#', 'LCPTXT',   ' = ', inp%LCPTXT
        write(io,'(A,A12,A3,L6)')     '#', 'LHOLE',    ' = ', inp%LHOLE

        if (inp%EPCTYPE==2) &
          write(io,'(A,A12,A3,A)') '#', 'MDFIL', ' = ', TRIM(ADJUSTL(inp%FILMD))
        write(io,'(A,A12,A3,A)') '#', 'EPMFIL', ' = ', TRIM(ADJUSTL(inp%FILEPM))
      end do

    end if

    Nt = inp%NAMDTIME / inp%POTIM
    do tion=1, Nt
      write(unit=24, fmt='(*(G20.10))') tion * inp%POTIM, &
        SUM(ks%eigKs(:,tion) * ks%sh_pops(:,tion)) / inp%NINIBS, &
        (ks%sh_pops(i,tion), i=1, ks%ndim)
      ! write(unit=25, fmt="(2G20.10, *( ' ( ',G20.10,' , ',G20.10,' ) ' ) )") &
      write(unit=25, fmt='(*(G20.10))') tion * inp%POTIM, &
        SUM(ks%eigKs(:,tion) * ks%pop_a(:,tion)), &
      ! (ks%psi_a(i,tion), i=1, ks%ndim)
        (ks%pop_a(i,tion), i=1, ks%ndim)
    end do

    close(24)
    close(25)

  end subroutine

  subroutine printPHPROP(ks, inp, olap, isample)
    implicit none
    type(TDKS), intent(in) :: ks
    type(namdInfo), intent(in) :: inp
    type(overlap), intent(in) :: olap
    integer, intent(in) :: isample

    real(kind=q), allocatable, dimension(:,:) :: pops
    integer :: i, j, tion, Nt, ierr, io, im, NM, Navg
    integer :: order, ntemp, steps
    character(len=48) :: mtag

    Nt = inp%NAMDTIME / inp%POTIM

    if (Nt<1000) then
      steps = 1
    else
      order = int( LOG10(REAL(Nt)) )
      ntemp = int( Nt / (10**order) )
      if (ntemp < 2) then
        steps = 1 * 10**(order-3)
      else if (ntemp < 5) then
        steps = 2 * 10**(order-3)
      else
        steps = 5 * 10**(order-3)
      end if
    end if

    Navg = inp%NTRAJ * isample * inp%NINIBS
    allocate(pops(inp%NQPOINTS, Nt))
    if (inp%NQPOINTS * inp%NMODES * Nt / steps > 3e7) &
      write(*,'(A)') "Writing PHPROP files, please wait!"

    do im=1, inp%NMODES

      write(mtag, *) im

      open(unit=26, file='PHPROP.' // trim(adjustl(mtag)), &
           status='unknown', action='write', iostat=ierr)
      if (ierr /= 0) then
        write(*,*) "PHPROP file I/O error!"
        stop
      end if

      io = 26
      write(io,'(A,A12,A3,I6)')     '#', 'BMIN',     ' = ', inp%BMIN
      write(io,'(A,A12,A3,I6)')     '#', 'BMAX',     ' = ', inp%BMAX
      write(io,'(A,A12,A3,I6)')     '#', 'KMIN',     ' = ', inp%KMIN
      write(io,'(A,A12,A3,I6)')     '#', 'KMAX',     ' = ', inp%KMAX
      if (inp%EMIN > -1.0E5_q) &
        write(io,'(A,A12,A3,F6.2)') '#', 'EMIN',     ' = ', inp%EMIN
      if (inp%EMAX <  1.0E5_q) &
        write(io,'(A,A12,A3,F6.2)') '#', 'EMAX',     ' = ', inp%EMAX

      write(io,'(A,A12,A3,I6)')     '#', 'NBASIS',   ' = ', inp%NBASIS
      write(io,'(A,A12,A3,I6)')     '#', 'NBANDS',   ' = ', inp%NBANDS
      write(io,'(A,A12,A3,I6)')     '#', 'NKPOINTS', ' = ', inp%NKPOINTS
      ! write(io,'(A,A12,A3,I6)')     '#', 'INIBAND',  ' = ', inp%INIBAND
      ! write(io,'(A,A12,A3,I6)')     '#', 'INIKPT',   ' = ', inp%INIKPT

      write(io,'(A,A12,A3,I6)')     '#', 'NSW',      ' = ', inp%NSW
      write(io,'(A,A12,A3,F6.1)')   '#', 'POTIM',    ' = ', inp%POTIM
      write(io,'(A,A12,A3,F6.1)')   '#', 'TEMP',     ' = ', inp%TEMP
      write(io,'(A,A12,A3,I6)')     '#', 'NAMDTINI', ' = ', inp%NAMDTINI
      write(io,'(A,A12,A3,I6)')     '#', 'NAMDTIME', ' = ', inp%NAMDTIME
      write(io,'(A,A12,A3,I6)')     '#', 'NTRAJ',    ' = ', inp%NTRAJ
      write(io,'(A,A12,A3,I6)')     '#', 'NELM',     ' = ', inp%NELM

      write(io,'(A,A12,A3,L6)')     '#', 'LEPC',     ' = ', inp%LEPC
      write(io,'(A,A12,A3,L6)')     '#', 'LARGEBS',  ' = ', inp%LARGEBS
      write(io,'(A,A12,A3,I6)')     '#', 'EPCTYPE',  ' = ', inp%EPCTYPE
      write(io,'(A,A12,A3,L6)')     '#', 'LBASSEL',  ' = ', inp%LBASSEL
      write(io,'(A,A12,A3,L6)')     '#', 'LSORT',    ' = ', inp%LSORT
      write(io,'(A,A12,A3,L6)')     '#', 'LCPTXT',   ' = ', inp%LCPTXT
      write(io,'(A,A12,A3,L6)')     '#', 'LHOLE',    ' = ', inp%LHOLE

      if (inp%EPCTYPE==2) &
        write(io,'(A,A12,A3,A)') '#', 'MDFIL', ' = ', TRIM(ADJUSTL(inp%FILMD))
      write(io,'(A,A12,A3,A)') '#', 'EPMFIL', ' = ', TRIM(ADJUSTL(inp%FILEPM))

      pops = ks%ph_pops(:,im,:) / Navg

      do tion=1, Nt
        ! if ( (MOD(tion, steps) .NE. 0) .AND. (tion .NE. Nt) ) then
        if (MOD(tion, steps) .NE. 0) then
          pops(:,tion+1) = pops(:,tion) + pops(:, tion+1)
          cycle
        end if
        ! prevent output error for small value
        pops(:,tion) = pops(:,tion) + 1.0E-30
        write(unit=26, fmt='(*(G20.10))') &
            tion * inp%POTIM, SUM( olap%Phfreq(:,im) * pops(:,tion) ), &
            (pops(i,tion), i=1, inp%NQPOINTS)
      end do

      close(26)

    end do


  end subroutine


end module

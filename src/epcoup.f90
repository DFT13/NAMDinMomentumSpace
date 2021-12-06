module epcoup
  use prec
  use constants
  use fileio
  use couplings
  use hdf5

  implicit none

  type epCoupling
    integer :: nbands, nkpts, nmodes, nqpts, natepc, natmd
    integer, allocatable, dimension(:) :: atmap
    !! mapping of each atom in MD cell to atom in unit cell for epc calculation.
    integer, allocatable, dimension(:,:) :: Rp
    !! number of lattice vector of each atom in MD cell, Rp(natmd,3)
    integer, allocatable, dimension(:,:) :: kkqmap
    !! map ik & jk of electronic states to q of phonon modes.
    real(kind=q), allocatable, dimension(:) :: mass
    real(kind=q), allocatable, dimension(:,:,:) :: displ
    real(kind=q), allocatable, dimension(:,:) :: kpts, qpts
    real(kind=q), allocatable, dimension(:,:) :: cellep, cellmd
    complex(kind=q), allocatable, dimension(:,:,:,:) :: phmodes
  end type

  contains

  subroutine releaseEPC(epc)
    implicit none

    type(epCoupling), intent(inout) :: epc

    if ( allocated(epc%Rp) ) deallocate(epc%Rp)
    if ( allocated(epc%atmap) ) deallocate(epc%atmap)
    if ( allocated(epc%kkqmap) ) deallocate(epc%kkqmap)
    if ( allocated(epc%kpts) ) deallocate(epc%kpts)
    if ( allocated(epc%qpts) ) deallocate(epc%qpts)
    if ( allocated(epc%cellep) ) deallocate(epc%cellep)
    if ( allocated(epc%cellmd) ) deallocate(epc%cellmd)
    if ( allocated(epc%displ) ) deallocate(epc%displ)
    if ( allocated(epc%phmodes) ) deallocate(epc%phmodes)

  end subroutine


  subroutine readEPCinfo(inp, epc)
    implicit none

    type(namdInfo), intent(inout) :: inp
    type(epCoupling), intent(inout) :: epc

    integer :: hdferror, info(4)
    integer(hsize_t) :: dim1(1)
    integer :: nk, nq, nb, nm, nat
    integer(hid_t) :: file_id, gr_id, dset_id
    character(len=256) :: fname, grname, dsetname

    fname = inp%FILEPM
    call h5open_f(hdferror)
    call h5fopen_f(fname, H5F_ACC_RDONLY_F, file_id, hdferror)
    grname = 'el_ph_band_info'
    call h5gopen_f(file_id, grname, gr_id, hdferror)
    dsetname = 'information'
    dim1 = shape(info, kind=hsize_t)
    call h5dopen_f(gr_id, dsetname, dset_id, hdferror)

    call h5dread_f(dset_id, H5T_NATIVE_INTEGER, info, dim1, hdferror)

    call h5dclose_f(dset_id, hdferror)
    call h5gclose_f(gr_id, hdferror)
    call h5fclose_f(file_id, hdferror)

    nk = info(1); epc%nkpts  = nk
    nq = info(2); epc%nqpts  = nq
    nb = info(3); epc%nbands = nb
    nm = info(4); epc%nmodes = nm
    nat = nm/3  ; epc%natepc = nat

    if (inp%NBANDS .NE. nb) then
      write(*,*) 'NBANDS seems to be wrong!'
      stop
    end if
    if (inp%NKPOINTS .NE. nk) then
      write(*,*) 'NKPOINTS seems to be wrong!'
      stop
    end if
    if ( (inp%NMODES .NE. 1) .AND. (inp%NMODES .NE. nm) ) then
      write(*,*) 'NMODES seems to be wrong!'
      stop
    end if
    if ( inp%Np==1 ) inp%Np = nq
    inp%NMODES = nm

  end subroutine


  subroutine readEPCpert(inp, epc, olap)
    ! Read information of e-ph coupling from perturbo.x output file
    ! (prefix_ephmat_p1.h5), which is in form of hdf5.
    ! Extract informations include: el bands, ph dispersion, k & q lists, ephmat

    implicit none

    type(namdInfo), intent(in) :: inp
    type(epCoupling), intent(inout) :: epc
    type(overlap), intent(inout) :: olap

    integer :: hdferror
    integer :: nk, nq, nb, nm, nat
    integer :: ib, jb, ik, jk, im, iq, it, ibas, jbas
    integer(hid_t) :: file_id, gr_id, dset_id
    integer(hsize_t) :: dim1(1), dim2(2), dim4(4)
    character(len=72) :: tagk, fname, grname, dsetname
    real(kind=q), allocatable, dimension(:,:) :: entemp, freqtemp
    real(kind=q), allocatable, dimension(:,:) :: kqltemp, pos, lattvec
    real(kind=q), allocatable, dimension(:,:,:,:) :: eptemp_r, eptemp_i, phmtemp
    complex(kind=q), allocatable, dimension(:,:,:,:) :: eptemp

    nk  = epc%nkpts
    nq  = epc%nqpts
    nb  = epc%nbands
    nm  = epc%nmodes
    nat = epc%natepc

    write(*,*) "Reading ephmat.h5 file."

    fname = inp%FILEPM

    call h5open_f(hdferror)
    call h5fopen_f(fname, H5F_ACC_RDONLY_F, file_id, hdferror)

    ! Read el bands, ph dispersion, k & q lists.
    grname = 'el_ph_band_info'
    call h5gopen_f(file_id, grname, gr_id, hdferror)

    dsetname = 'k_list'
    allocate(kqltemp(3,nk), epc%kpts(nk,3))
    dim2 = shape(kqltemp, kind=hsize_t)
    call h5dopen_f(gr_id, dsetname, dset_id, hdferror)
    call h5dread_f(dset_id, H5T_NATIVE_DOUBLE, kqltemp, dim2, hdferror)
    call h5dclose_f(dset_id, hdferror)
    epc%kpts = transpose(kqltemp)
    deallocate(kqltemp)

    dsetname = 'q_list'
    allocate(kqltemp(3,nq), epc%qpts(nq,3))
    dim2 = shape(kqltemp, kind=hsize_t)
    call h5dopen_f(gr_id, dsetname, dset_id, hdferror)
    call h5dread_f(dset_id, H5T_NATIVE_DOUBLE, kqltemp, dim2, hdferror)
    call h5dclose_f(dset_id, hdferror)
    epc%qpts = transpose(kqltemp)
    deallocate(kqltemp)

    dsetname = 'el_band_eV'
    allocate(entemp(nb,nk))
    dim2 = shape(entemp, kind=hsize_t)
    call h5dopen_f(gr_id, dsetname, dset_id, hdferror)
    call h5dread_f(dset_id, H5T_NATIVE_DOUBLE, entemp, dim2, hdferror)
    call h5dclose_f(dset_id, hdferror)

    do ik=1,nk
      do ib=1,nb
        olap%Eig(ib+nb*(ik-1),:) = entemp(ib,ik)
      end do
    end do

    dsetname = 'ph_disp_meV'
    allocate(freqtemp(nm,nq))
    dim2 = shape(freqtemp, kind=hsize_t)
    call h5dopen_f(gr_id, dsetname, dset_id, hdferror)
    call h5dread_f(dset_id, H5T_NATIVE_DOUBLE, freqtemp, dim2, hdferror)
    call h5dclose_f(dset_id, hdferror)
    freqtemp = freqtemp / 1000.0_q ! transform unit to eV


    if (inp%EPCTYPE==2) then
      dsetname = 'mass_a.u.'
      allocate(epc%mass(nat))
      dim1 = shape(epc%mass, kind=hsize_t)
      call h5dopen_f(gr_id, dsetname, dset_id, hdferror)
      call h5dread_f(dset_id, H5T_NATIVE_DOUBLE, epc%mass, dim1, hdferror)
      call h5dclose_f(dset_id, hdferror)

      dsetname = 'lattice_vec_angstrom'
      allocate(epc%cellep(nat+3,3), lattvec(3,3))
      dim2 = shape(lattvec, kind=hsize_t)
      call h5dopen_f(gr_id, dsetname, dset_id, hdferror)
      call h5dread_f(dset_id, H5T_NATIVE_DOUBLE, lattvec, dim2, hdferror)
      call h5dclose_f(dset_id, hdferror)
      epc%cellep(:3,:) = transpose(lattvec)

      dsetname = 'atom_pos'
      allocate(pos(3,nat))
      dim2 = shape(pos, kind=hsize_t)
      call h5dopen_f(gr_id, dsetname, dset_id, hdferror)
      call h5dread_f(dset_id, H5T_NATIVE_DOUBLE, pos, dim2, hdferror)
      call h5dclose_f(dset_id, hdferror)
      epc%cellep(4:,:) = transpose(pos)

      dsetname = 'phmod_ev_r'
      allocate(epc%phmodes(nq, nm, nat, 3))
      allocate(phmtemp(nq, nm, nat, 3))
      dim4 = shape(phmtemp, kind=hsize_t)
      call h5dopen_f(gr_id, dsetname, dset_id, hdferror)
      call h5dread_f(dset_id, H5T_NATIVE_DOUBLE, phmtemp, dim2, hdferror)
      call h5dclose_f(dset_id, hdferror)
      epc%phmodes = phmtemp

      dsetname = 'phmod_ev_i'
      call h5dopen_f(gr_id, dsetname, dset_id, hdferror)
      call h5dread_f(dset_id, H5T_NATIVE_DOUBLE, phmtemp, dim2, hdferror)
      call h5dclose_f(dset_id, hdferror)
      epc%phmodes = epc%phmodes + imgUnit * phmtemp
    end if

    call h5gclose_f(gr_id, hdferror)


    ! Read e-ph matrix for every k.
    grname = 'g_ephmat_total_meV'
    call h5gopen_f(file_id, grname, gr_id, hdferror)
    allocate(eptemp(nb, nb, nm, nq))
    allocate(eptemp_r(nb, nb, nm, nq))
    allocate(eptemp_i(nb, nb, nm, nq))

    call kqMatch(epc)

    do ik=1,nk

      write(tagk, '(I8)') ik

      dsetname = 'g_ik_r_' // trim( adjustl(tagk) )
      dim4 = shape(eptemp, kind=hsize_t)
      call h5dopen_f(gr_id, dsetname, dset_id, hdferror)
      call h5dread_f(dset_id, H5T_NATIVE_DOUBLE, eptemp_r, dim4, hdferror)
      call h5dclose_f(dset_id, hdferror)
      ! if (ik==1) write(*,*) eptemp(1,1,:,2)

      dsetname = 'g_ik_i_' // trim( adjustl(tagk) )
      dim4 = shape(eptemp, kind=hsize_t)
      call h5dopen_f(gr_id, dsetname, dset_id, hdferror)
      call h5dread_f(dset_id, H5T_NATIVE_DOUBLE, eptemp_i, dim4, hdferror)
      call h5dclose_f(dset_id, hdferror)

      eptemp = ( eptemp_r + imgUnit * eptemp_i ) / 1000.0_q

      do jk=1,nk

        iq = epc%kkqmap(ik, jk)
        if (iq<0) cycle

        do im=1,nm

          if (freqtemp(im,iq)<5.0E-3_q) cycle

          do jb=1,nb
            do ib=1,nb

              ibas = nb*(ik-1)+ib
              jbas = nb*(jk-1)+jb
              olap%kkqmap(ibas, jbas) = iq
              olap%Phfreq(iq,im) = freqtemp(im,iq)
              olap%gij(ibas, jbas, im) = eptemp(ib, jb, im, iq)

            end do ! ib loop
          end do ! jb loop

        enddo ! im loop

      enddo ! jk loop

    enddo ! ik loop

    call h5gclose_f(gr_id, hdferror)

    call h5fclose_f(file_id, hdferror)

  end subroutine


  subroutine readDISPL(inp, epc)
    implicit none

    type(namdInfo), intent(in) :: inp
    type(epCoupling), intent(inout) :: epc

    real(kind=q) :: scal, dr, lattvec(3,3), temp(3)
    integer :: ierr, i, iax, ia, it
    integer :: nat, nsw

    nsw = inp%NSW
    write(*,*) 'Reading MD traj.'

    open(unit=35, file=inp%FILMD, status='unknown', action='read', iostat=ierr)
    if (ierr /= 0) then
      write(*,*) "XDATCAR file does NOT exist!"
      stop
    end if

    read(unit=35, fmt=*)
    read(unit=35, fmt=*) scal
    do i=1,3
      read(unit=35, fmt=*) (lattvec(i, iax), iax=1,3)
      lattvec(i,:) = lattvec(i,:) * scal
    end do
    read(unit=35, fmt=*)
    read(unit=35, fmt=*) nat
    epc%natmd = nat

    allocate(epc%displ(nsw, nat, 3))

    do it=1,nsw
      read(unit=35, fmt=*)
      do ia=1,nat
        read(unit=35, fmt=*) (epc%displ(it, ia, iax), iax=1, 3)
        do iax=1,3
          if (it==1) cycle
          ! Modify atom position if atom moves to other cell.
          dr = epc%displ(it, ia, iax) - epc%displ(it-1, ia, iax)
          if (dr>0.9) then
            epc%displ(it, ia, iax) = epc%displ(it, ia, iax) - 1
          else if (dr<-0.9) then
            epc%displ(it, ia, iax) = epc%displ(it, ia, iax) + 1
          endif
        enddo
      end do
    end do

    allocate(epc%cellmd(nat+3, 3))
    epc%cellmd(:3,:) = lattvec
    ! epc%cellmd(4:,:) = epc%displ(1,:,:)
    do ia=1,nat
      do iax=1,3
        epc%cellmd(ia+3, iax) = SUM(epc%displ(:, ia, iax)) / nsw
      end do
    end do

    do it=1,nsw
      do ia=1,nat
        temp = 0.0_q
        do iax=1,3
          ! minus average coordinates.
          ! change from crastal coordinates to cartesian coordinates.
          temp = temp + ( epc%displ(it,ia,iax) - epc%cellmd(ia+3, iax) ) * &
                 lattvec(iax, :)
        end do
        epc%displ(it,ia,:) = temp
      end do
    end do

    close(unit=35)

  end subroutine


  subroutine cellPROJ(epc)
    ! Calculate cell numbers for each atom of md cell
    ! Project from phonon cell to md cell.
    implicit none

    integer :: iax, ia, ja, i, N(3)
    !! scale numbers of md cell compared with phonon cell
    real(kind=q) :: dr(3), temp1(3), temp2(3)

    type(epCoupling), intent(inout) :: epc

    allocate(epc%Rp(epc%natmd,3), epc%atmap(epc%natmd))

    do iax=1,3
      ! ONLY suit for sample shape cells !
      N(iax) = NINT( SUM(epc%cellmd(iax,:)) / SUM(epc%cellep(iax,:)) )
    enddo

    do ia=1,epc%natmd
      temp1 = 9999.9
      do ja=1,epc%natepc
        dr = epc%cellmd(ia+3,:) * N - epc%cellep(ja+3,:)
        do iax=1,3
          temp2(iax) = ABS( dr(iax) - NINT(dr(iax)) )
        enddo
        if (SUM(temp2)<SUM(temp1)) then
          temp1 = temp2
          epc%atmap(ia) = ja
          epc%Rp(ia,:) = (/(MOD(NINT(dr(i)),N(i)), i=1,3)/)
        endif
      enddo
    enddo

  end subroutine


  subroutine phDecomp(inp, olap, epc)
    ! Project the atomic motion from an MD simulation to phonon modes.
    implicit none

    type(namdInfo), intent(in) :: inp
    type(overlap), intent(inout) :: olap
    type(epCoupling), intent(inout) :: epc

    ! Temporary normal mode coordinate
    complex(kind=q) :: temp
    complex(kind=q), allocatable, dimension(:,:) :: eiqR
    real(kind=q) :: lqvtemp, lqv, theta, displ(3), Np
    integer :: iq, im, ia, ja, iax, it
    integer :: nqs, nmodes, nat, nsw
    integer :: ik, jk, nks, ib, jb, ibas, jbas, nb

    call readDISPL(inp, epc)
    call cellPROJ(epc)

    write(*,*) "Decomposing phonon modes from MD traj."

    nks = epc%nkpts
    nb = inp%NBANDS
    nqs = epc%nqpts
    nmodes = epc%nmodes
    nsw = inp%NSW
    nat = epc%natmd

    allocate(eiqR(nqs,nat))

    do iq=1,nqs
      do ia=1,nat
        theta = 2 * PI * DOT_PRODUCT( epc%qpts(iq,:), epc%Rp(ia,:) )
        eiqR(iq, ia) = EXP(-imgUnit*theta)
      end do
    end do

    lqvtemp = hbar * SQRT( EVTOJ / (2.0_q*AMTOKG) ) * 1.0E-5_q

    do iq=1,nqs
      do im=1,nmodes
        ! unit of Angstrom
        lqv = lqvtemp / SQRT(olap%Phfreq(iq,im))
        do it=1,nsw-1
          temp = cero
          do ia=1,nat
            ja = epc%atmap(ia)
            temp = temp + eiqR(iq,ia) * SQRT(epc%mass(ja)) * &
                   DOT_PRODUCT( CONJG(epc%phmodes(iq, im, ja, :)), &
                   epc%displ(it, ia, :) )
          end do
          olap%PhQ(iq,im,:,it) = temp / lqv / 2.0_q
        end do
      end do
    end do

    ! Np is the number of unit cells in MD cell.
    Np = epc%natmd / epc%natepc
    olap%PhQ = olap%PhQ / SQRT(Np)

  end subroutine


  subroutine kqMatch(epc)
    implicit none

    type(epCoupling), intent(inout) :: epc

    real(kind=q) :: norm
    real(kind=q) :: dkq(3), dq(3)
    integer :: ik, jk, iq, jq, iax

    norm = 0.001
    ! If k1-k2 < norm, recognize k1 and k2 as same k point.
    ! So, number of kx, ky, kz or qx, qy, qz must not supass 1/norm = 1000

    allocate(epc%kkqmap(epc%nkpts,epc%nkpts))

    epc%kkqmap = -1

    do ik=1,epc%nkpts
      do jk=1,epc%nkpts
        do iq=1,epc%nqpts
          dkq = epc%kpts(ik,:) - epc%kpts(jk,:) - epc%qpts(iq,:)
          do iax=1,3
            dkq(iax) = ABS(dkq(iax)-NINT(dkq(iax)))
          end do
          if (SUM(dkq)<norm) then
              epc%kkqmap(ik,jk) = iq
              exit
          end if
        end do
      end do
    end do

  end subroutine


  subroutine calcPhQ(olap, inp)
    implicit none

    type(overlap), intent(inout) :: olap
    type(namdInfo), intent(in) :: inp

    integer :: iq, nq, im, nmodes, it, nsw
    real(kind=q) :: kbT, phn, phQtemp
    complex(kind=q) :: iw, iwtemp

    nq = olap%NQ
    nmodes = olap%NMODES
    nsw = olap%TSTEPS

    kbT = inp%TEMP * BOLKEV
    iwtemp = imgUnit * inp%POTIM / hbar

    do iq=1, nq
      do im=1, nmodes
        if (olap%Phfreq(iq,im)<5.0E-3_q) cycle
        phn = 1.0 / ( exp(olap%Phfreq(iq,im)/kbT) - 1.0 )
        iw = iwtemp * olap%Phfreq(iq,im)
        olap%PhQ(iq,im,:,:) = SQRT(phn+0.5)
        phQtemp = SQRT(phn+0.5)
        do it=1, nsw-1
          olap%PhQ(iq,im,1,it) = phQtemp * exp(-iw*it)
          olap%PhQ(iq,im,2,it) = phQtemp * exp(iw*it)
        end do
      end do
    end do

  end subroutine

  subroutine calcEPC_LBS(olap, inp)
  ! EPC calculations for large basis set.
    implicit none

    type(overlap), intent(inout) :: olap
    type(namdInfo), intent(in) :: inp
    integer :: nb, nm
    integer :: ib, jb, im, iq
    real(kind=q) :: dE, dE1, dE2
    real(kind=q) :: kbT
    complex(kind=q) :: idwt

    write(*,*) "Calculating e-ph couplings."

    nb  = olap%NBANDS
    nm  = olap%NMODES
    kbT = inp%TEMP * BOLKEV
    idwt = imgUnit / kbT * TPI

    allocate(olap%EPcoup(nb, nb, nm, 2, 1))
    olap%EPcoup = cero

    do ib=1,nb
     do jb=ib,nb

       dE = olap%Eig(ib,1) - olap%Eig(jb,1)
       iq = olap%kkqmap(ib,jb)
       if (iq<0) cycle

       do im=1,nm
         if (jb==ib) olap%gij(ib,ib,im)= ABS(olap%gij(ib,ib,im))
         dE1 = dE - olap%Phfreq(iq,im) - 1.0E-8_q
         olap%EPcoup(ib,jb,im,1,1) = olap%gij(ib,jb,im) * &
           ( exp(idwt * dE1) - 1.0 ) / ( idwt * dE1 )
         dE2 = dE + olap%Phfreq(iq,im) + 1.0E-8_q
         olap%EPcoup(ib,jb,im,2,1) = olap%gij(ib,jb,im) * &
           ( exp(idwt * dE2) - 1.0 ) / ( idwt * dE2 )
       end do ! im loop

       ! olap%gij(jb,ib,:) = CONJG(olap%gij(ib,jb,:))
       olap%EPcoup(jb,ib,:,:,:) = CONJG(olap%EPcoup(ib,jb,:,:,:))

     end do
    end do
    olap%gij = olap%gij / SQRT(olap%Np)
    olap%EPcoup = olap%EPcoup / SQRT(olap%Np)

  end subroutine


  subroutine calcEPC(olap, inp)
    implicit none

    type(overlap), intent(inout) :: olap
    type(namdInfo), intent(in) :: inp

    integer :: nb, nm, nsw
    integer :: ib, jb, im, it, iq
    ! zero-point displacement amplitude
    real(kind=q) :: lqvtemp, lqv
    real(kind=q) :: kbT, phn
    real(kind=q) :: dE, dE1, dE2
    complex(kind=q) :: iw, iwtemp, idwt, eptemp

    nsw = inp%NSW
    nb  = olap%NBANDS
    nm  = olap%NMODES
    kbT = inp%TEMP * BOLKEV
    idwt = imgUnit / kbT * TPI
    ! iwt = i * (dE/hbar) * (hbar/kbT)

    write(*,*) "Calculating e-ph couplings."

    allocate(olap%Dij(nb, nb, nsw-1))
    olap%Dij = cero


    iwtemp = imgUnit * inp%POTIM / hbar
    allocate(olap%EPcoup(nb, nb, nm, 2, nsw-1))
    olap%EPcoup = cero

    do ib=1,nb
     do jb=ib,nb
       dE = olap%Eig(ib,1) - olap%Eig(jb,1)
       iq = olap%kkqmap(ib,jb)
       if (iq<0) cycle
       do im=1,nm

         ! if (olap%Phfreq(iq, im)<5.0E-3_q) cycle
         if (jb==ib) then
           olap%gij(ib,ib,im)= ABS(olap%gij(ib,ib,im))
           if (olap%COUPTYPE==2) &
             olap%PhQ(iq,im,:,:)= ABS(olap%PhQ(iq,im,:,:))
         end if

         olap%EPcoup(ib,jb,im,:,:) = olap%gij(ib,jb,im) * olap%PhQ(iq,im,:,:)

         olap%Dij(ib,jb,:) = olap%Dij(ib,jb,:) + &
             SUM(olap%EPcoup(ib,jb,im,:,:), dim=1)


         dE1 = dE - olap%Phfreq(iq,im) - 1.0E-8_q
         olap%EPcoup(ib,jb,im,1,:) = olap%EPcoup(ib,jb,im,1,:) * &
           ( exp(idwt * dE1) - 1.0 ) / ( idwt * dE1 )
         dE2 = dE + olap%Phfreq(iq,im) + 1.0E-8_q
         olap%EPcoup(ib,jb,im,2,:) = olap%EPcoup(ib,jb,im,2,:) * &
           ( exp(idwt * dE2) - 1.0 ) / ( idwt * dE2 )

       end do ! im loop

       olap%Dij(jb,ib,:) = CONJG(olap%Dij(ib,jb,:))
       olap%EPcoup(jb,ib,:,:,:) = CONJG(olap%EPcoup(ib,jb,:,:,:))

     end do
    end do

    olap%Dij = olap%Dij / SQRT(olap%Np)
    if (olap%COUPTYPE==1) then
      olap%EPcoup = olap%EPcoup / SQRT(olap%Np)
    else
      olap%EPcoup = olap%EPcoup / SQRT(olap%Np * 0.5)
    end if

    call releaseOlap(olap)

  end subroutine


  subroutine TDepCoupIJ(olap, olap_sec, inp, epc)
    implicit none

    type(namdInfo), intent(inout) :: inp
    type(epCoupling), intent(inout) :: epc
    type(overlap), intent(inout) :: olap
    type(overlap), intent(inout) :: olap_sec

    integer :: nmodes, nb, nsw
    logical :: lcoup

    write(*,*)
    write(*,'(A)') &
      "------------------------------------------------------------"

    call readEPCinfo(inp, epc)

    if (inp%LCPTXT .and. inp%LBASSEL) then

      if (inp%LARGEBS) then
        write(*,*) "For large basis set, LCPEXT is not available!"
        write(*,*)
        stop
      end if

      write(*,*) "Reading couplings from TXT files..."

      call readBasis(inp)

      nsw = inp%NSW
      nb = inp%NBASIS
      nmodes = inp%NMODES
      allocate(olap_sec%Dij(nb, nb, nsw-1))
      allocate(olap_sec%EPcoup(nb, nb, nmodes, 1, nsw-1))
      olap%Dij = cero ; olap%EPcoup = cero
      call initOlap(olap_sec, inp, epc%nqpts, nb)

      ! call readNaEig(olap_sec, inp)
      call readEPTXTs(olap_sec)
      call releaseOlap(olap_sec)

    else

      inquire(file='EPCAR', exist=lcoup)
      call initOlap(olap, inp, epc%nqpts, inp%NBANDS * inp%NKPOINTS)
      if (lcoup) then
        call CoupFromFileEP(olap)
      else
        if (inp%EPCTYPE==1) then
          write(*,*) "TypeI e-ph coupling calculation."
          call readEPCpert(inp, epc, olap)
          call calcPhQ(olap, inp)
        else
          write(*,*) "TypeII e-ph coupling calculation."
          call readEPCpert(inp, epc, olap)
          call phDecomp(inp, olap, epc)
        end if
        ! call CoupToFileEP(olap)
      end if

      call copyToSec(olap, olap_sec, inp)
      if (inp%LARGEBS) then
        call calcEPC_LBS(olap_sec, inp)
        call writeTXT_LBS(olap_sec)
      else
        call calcEPC(olap_sec, inp)
        call writeEPTXTs(olap_sec)
      end if

      call releaseEPC(epc)
      call releaseOlap(olap)
      deallocate(olap%Eig)

    end if

    write(*,*) "Done!"
    write(*,'(A)') &
      "------------------------------------------------------------"
    write(*,*)

  end subroutine


  subroutine readBasis(inp)
    implicit none

    type(namdInfo), intent(inout) :: inp
    integer :: ierr, ibas, ik, ib

    open(unit=38, file='BASSEL', status='unknown', action='read', iostat=ierr)

    if (ierr /= 0) then
      write(*,*) "BASSEL file does NOT exist!"
      stop
    end if

    inp%BASSEL = -1
    read(unit=38, fmt=*) inp%NBASIS
    allocate(inp%BASLIST(inp%NBASIS, 3))
    do ibas=1,inp%NBASIS
      read(unit=38, fmt=*) ik, ib
      inp%BASSEL(ik, ib) = ibas
      inp%BASLIST(ibas, 1) = ik
      inp%BASLIST(ibas, 2) = ib
    end do

    close(unit=38)

  end subroutine


  subroutine selBasis(inp, olap)
    implicit none

    type(overlap), intent(in) :: olap
    type(namdInfo), intent(inout) :: inp

    integer :: ik, ib, nb, ibas
    real :: emin, emax

    nb = inp%NBANDS
    emin = inp%EMIN
    emax = inp%EMAX

    inp%NBASIS = 0
    inp%BASSEL = -1

    do ik=inp%KMIN, inp%KMAX
      do ib=inp%BMIN, inp%BMAX
        if ( olap%Eig((ik-1)*nb+ib, 1)>emin .and. &
             olap%Eig((ik-1)*nb+ib, 1)<emax ) then
          inp%NBASIS = inp%NBASIS + 1
          inp%BASSEL(ik,ib) = inp%NBASIS
        end if
      end do
    end do

    allocate(inp%BASLIST(inp%NBASIS, 3))

    open(unit=39, file='BASSEL', status='unknown', action='write')

    write(unit=39, fmt='(I18)') inp%NBASIS

    ibas = 0
    do ik=inp%KMIN, inp%KMAX
      do ib=inp%BMIN, inp%BMAX
        if (inp%BASSEL(ik,ib)>0) then
          ibas = ibas + 1
          inp%BASLIST(ibas, 1) = ik
          inp%BASLIST(ibas, 2) = ib
          write(unit=39, fmt='(2I12)') ik, ib
        end if
      end do
    end do

    close(unit=39)

    !! For array element inp%BASSEL(ik,ib),
    !! 0 represent ik,ib state isn't selected as basis;
    !! number >0 represent ik,ib state is selected as basis,
    !! and the number is the state's serial number among the basises.

  end subroutine


  subroutine sortBasis(inp, olap)
    implicit none

    type(overlap), intent(in) :: olap
    type(namdInfo), intent(inout) :: inp

    integer :: ibas, i, j, ik, ib, nb, nbas
    integer :: temp(3)

    nb = inp%NBANDS
    nbas = inp%NBASIS
    do ibas=1,nbas
      ik = inp%BASLIST(ibas,1)
      ib = inp%BASLIST(ibas,2)
      inp%BASLIST(ibas,3) = olap%Eig((ik-1)*nb+ib, 1) * 1000
    end do

    do i=1,nbas-1
      do j=1,nbas-i
        if ( inp%BASLIST(j+1,3) < inp%BASLIST(j,3) ) then
          temp = inp%BASLIST(j,:)
          inp%BASLIST(j,:) = inp%BASLIST(j+1,:)
          inp%BASLIST(j+1,:) = temp
        end if
      end do
    end do

    open(unit=39, file='BASSEL', status='unknown', action='write')
    write(unit=39, fmt='(I18)') inp%NBASIS

    do ibas=1,nbas
      ik = inp%BASLIST(ibas,1)
      ib = inp%BASLIST(ibas,2)
      inp%BASSEL(ik, ib) = ibas
      write(unit=39, fmt='(2I12)') ik, ib
    end do
    close(unit=39)

  end subroutine


  subroutine initOlap(olap, inp, nq, nb)
    implicit none
    type(overlap), intent(inout) :: olap
    type(namdInfo), intent(in) :: inp
    integer, intent(in) :: nq, nb
    integer :: nmodes, nsw

    nmodes = inp%NMODES
    nsw = inp%NSW

    olap%NBANDS = nb
    olap%TSTEPS = inp%NSW
    olap%dt = inp%POTIM
    olap%NMODES = nmodes
    olap%COUPTYPE = inp%EPCTYPE
    olap%Np = inp%Np
    olap%NQ = nq

    allocate(olap%Eig(nb, nsw-1))
    allocate(olap%gij(nb, nb, nmodes))
    allocate(olap%Phfreq(nq, nmodes))
    allocate(olap%PhQ(nq, nmodes, 2, nsw-1))
    allocate(olap%kkqmap(nb,nb))

    olap%gij = cero
    olap%PhQ = cero
    olap%Phfreq = 0.0_q
    olap%Eig = 0.0_q
    olap%kkqmap = -1

  end subroutine


  subroutine releaseOlap(olap)
    implicit none
    type(overlap), intent(inout) :: olap

    if ( allocated(olap%gij) ) deallocate(olap%gij)
    if ( allocated(olap%Phfreq) ) deallocate(olap%Phfreq)
    if ( allocated(olap%PhQ) ) deallocate(olap%PhQ)

  end subroutine


  subroutine copyToSec(olap, olap_sec, inp)
    implicit none
    type(namdInfo), intent(inout) :: inp
    type(overlap), intent(inout) :: olap_sec
    type(overlap), intent(in) :: olap

    integer :: ik, jk, ib, jb, nb, ibas, jbas, nbas
    integer :: kmin, kmax, bmin, bmax
    real :: t

    if (inp%LBASSEL) then
    ! If .TRUE., BMIN, BMAX, KMIN, KMAX, EMIN, EMAX are ignored!!!
      call readBasis(inp)
    else
    ! selected basises whose energies are between EMIN ~ EMAX,
    ! in the range BMIN ~ BMAX and KMIN ~ KMAX.
      call selBasis(inp, olap)
    end if

    if (inp%LSORT) call sortBasis(inp, olap)
    call initOlap(olap_sec, inp, olap%NQ, inp%NBASIS)

    nb = inp%NBANDS
    nbas = inp%NBASIS

    do ibas=1,nbas
      ik = inp%BASLIST(ibas,1)
      ib = inp%BASLIST(ibas,2)
      olap_sec%Eig(ibas, :) = olap%Eig((ik-1)*nb+ib, :)
      do jbas=1,nbas
        jk = inp%BASLIST(jbas,1)
        jb = inp%BASLIST(jbas,2)

        olap_sec%kkqmap(ibas, jbas) = &
        olap%kkqmap( (ik-1)*nb+ib, (jk-1)*nb+jb )

        olap_sec%gij(ibas, jbas, :) = &
        olap%gij( (ik-1)*nb+ib, (jk-1)*nb+jb, : )

      end do
    end do

    olap_sec%Phfreq = olap%Phfreq
    olap_sec%PhQ = olap%PhQ

  end subroutine


  subroutine CoupToFileEP(olap)
    implicit none
    type(overlap), intent(in) :: olap

    ! Couplings are save to a binary file
    integer :: recordL, ierr, irec
    integer :: i, j, nb, im, nmodes, it
    ! to find out the record length
    complex(kind=q), allocatable, dimension(:)  :: values

    allocate(values(olap%NBANDS * olap%NBANDS))
    inquire (iolength=recordL) values
    deallocate(values)

    if (recordL<200) recordL=200 ! at least 25 real numbers (8 bytes)

    open(unit=30, file='EPCAR', access='direct', form='unformatted', &
         status='unknown', recl=recordL, iostat=ierr)
    if(ierr /= 0) then
        write(*,*) "File I/O error with EPCAR"
        write(*,*)
        stop
    end if

    irec = 1
    write(unit=30, rec=irec) &
        real(recordL,       kind=q), real(olap%NBANDS, kind=q), &
        real(olap%TSTEPS,   kind=q), real(olap%dt, kind=q), &
        real(olap%COUPTYPE, kind=q), real(olap%Np, kind=q), &
        real(olap%NMODES,   kind=q)

    nb = olap%NBANDS
    nmodes = olap%NMODES
    do im=1, nmodes
      irec = irec + 1
      ! Here we only save Eig(:,1)
      ! We suppose Eig(i,t) for any t does not change.
      ! write(unit=30, rec=irec) (olap%Eig(i,1), i=1,nb), &
      !     ((olap%Phfreq(i,j,im), i=1,nb), j=1,nb)
    end do
    do im=1, nmodes
      irec = irec + 1
      write(unit=30, rec=irec) ((olap%gij(i,j,im), i=1,nb), j=1,nb)
    end do
    if (olap%COUPTYPE==2) then
      do it=1,olap%TSTEPS-1
        do im=1, nmodes
          irec = irec + 1
          write(unit=30, rec=irec) ((olap%PhQ(i,j,im,it), i=1,nb), j=1,nb)
        end do
      end do
    end if

    close(unit=30)

  end subroutine


  subroutine CoupFromFileEP(olap)
    implicit none
    type(overlap), intent(inout) :: olap

    ! Couplings are save to a binary file
    integer :: irecordL, ierr, irec
    integer :: i, j, nb, im, nmodes, it
    real(kind=q) :: recordL, rnbands, rnsw, rdt, rctype, rnp, rnmodes

    open(unit=31, file='EPCAR', access='direct', form='unformatted', &
         status = 'unknown', recl=256, iostat=ierr)
    if(ierr /= 0) then
      write(*,*) "File I/O error with EPCAR"
      write(*,*)
      stop
    end if

    read(unit=31,rec=1) recordL, rnbands, rnsw, rdt, rctype, rnp, rnmodes
    ! write(*,*) recordL, rnbands, rnsw, rdt

    if (olap%NBANDS /= NINT(rnbands) .or. olap%TSTEPS /= NINT(rnsw) .or. &
       olap%COUPTYPE /= NINT(rctype) .or. olap%NMODES /= NINT(rnmodes)) then
      ! write(*,*) olap%NBANDS, NINT(rnbands), olap%TSTEPS, NINT(rnsw)
      write(*,*) "The EPCAR seems to be wrong..."
      write(*,*)
      stop
    end if

    close(31)

    irecordL = NINT(recordL)
    open(unit=31, file='EPCAR', access='direct', form='unformatted', &
         status = 'unknown', recl=irecordL, iostat=ierr)

    write(*,*) "Reading couplings from EPCAR..."

    irec = 1
    nb = olap%NBANDS
    nmodes = olap%NMODES
    olap%Np = rnp

    do im=1, nmodes
      irec = irec + 1
      ! We suppose Eig(i,t) for any t does not change.
      ! read(unit=31, rec=irec) (olap%Eig(i,1), i=1,nb), &
      !     ((olap%Phfreq(i,j,im), i=1,nb), j=1,nb)
      do i=1,nb
        olap%Eig(i,:) = olap%Eig(i,1)
      end do
    end do
    do im=1, nmodes
      irec = irec + 1
      read(unit=31, rec=irec) ((olap%gij(i,j,im), i=1,nb), j=1,nb)
    end do
    if (olap%COUPTYPE==2) then
      do it=1,olap%TSTEPS-1
        do im=1, nmodes
          irec = irec + 1
          read(unit=31, rec=irec) ((olap%PhQ(i,j,im,it), i=1,nb), j=1,nb)
        end do
      end do
    end if

    close(unit=31)

  end subroutine

  subroutine writeTXT_LBS(olap)
    implicit none

    type(overlap), intent(inout) :: olap
    integer :: im, nmodes, ib, jb, nb, iq, ierr, it, nsw
    real(kind=q), allocatable :: natxt(:,:), eptxt(:,:)

    nb = olap%NBANDS
    nmodes = olap%NMODES
    nsw = olap%TSTEPS

    allocate(natxt(nb,nb), eptxt(nb,nb))
    natxt = 0.0_q; eptxt = 0.0_q

    do ib=1,nb
      do jb=ib,nb
        iq = olap%kkqmap(ib,jb)
        do it=1,nsw-1
          natxt(ib,jb) = natxt(ib,jb) + ABS( SUM(olap%gij(ib,jb,:) * &
            SUM(olap%PhQ(iq,:,:,it), dim=2)) )
          eptxt(ib,jb) = eptxt(ib,jb) + &
            ABS( SUM(olap%EPcoup(ib,jb,:,:,1) * olap%PhQ(iq,:,:,it)) )
        end do
        natxt(jb,ib) = natxt(ib,jb)
        eptxt(jb,ib) = eptxt(ib,jb)
      end do
    end do
    natxt = natxt / (nsw-1)
    eptxt = eptxt / (nsw-1)

    open(unit=32, file='EIGTXT', status='unknown', action='write')
    open(unit=33, file='EPTXT', status='unknown', action='write')
    open(unit=34, file='EPECTXT', status='unknown', action='write')


    write(unit=32, fmt='(*(f12.6))') (olap%Eig(ib,1), ib=1,nb)
    write(unit=33, fmt='(*(f15.9))') (( natxt(ib,jb), jb=1,nb ), ib=1,nb)
    write(unit=34, fmt='(*(f15.9))') (( eptxt(ib,jb), jb=1,nb ), ib=1,nb)

    close(unit=32)
    close(unit=33)
    close(unit=34)

  end subroutine


  subroutine writeEPTXTs(olap)
    implicit none

    type(overlap), intent(in) :: olap
    integer :: im, nmodes, ib, jb, nb, it, nsw, ierr

    nb = olap%NBANDS
    nsw = olap%TSTEPS
    nmodes = olap%NMODES

    open(unit=32, file='EIGTXT',  status='unknown', action='write')
    open(unit=33, file='EPTXT',   status='unknown', action='write')
    open(unit=34, file='EPECTXT', status='unknown', action='write')

    do it=1,nsw-1
      write(unit=32, fmt='(*(f12.6))') (olap%Eig(ib,it), ib=1,nb)
      write(unit=33, fmt='(*(f15.9))') &
        ((olap%Dij(ib,jb,it), jb=1,nb), ib=1,nb)
      write(unit=34, fmt='(*(f15.9))') &
        (( SUM(olap%EPcoup(ib,jb,:,:,it)), jb=1,nb ), ib=1,nb)
    end do

    close(unit=32)
    close(unit=33)
    close(unit=34)

  end subroutine


  subroutine readEPTXTs(olap)
    implicit none

    type(overlap), intent(inout) :: olap
    integer :: im, nmodes, ib, jb, nb, it, nsw, ierr

    open(unit=32, file='EIGTXT', status='unknown', &
         action='read', iostat=ierr)
    if (ierr /= 0) then
      write(*,*) "EIGTXT does NOT exist!"
      write(*,*)
      stop
    end if
    open(unit=33, file='EPTXT', status='unknown', &
         action='read', iostat=ierr)
    if (ierr /= 0) then
      write(*,*) "EPTXT does NOT exist!"
      write(*,*)
      stop
    end if
    open(unit=34, file='EPECTXT', status='unknown', &
         action='read', iostat=ierr)
    if (ierr /= 0) then
      write(*,*) "EPECTXT does NOT exist!"
      write(*,*)
      stop
    end if

    nb = olap%NBANDS
    nsw = olap%TSTEPS
    do it=1,nsw-1
      read(unit=32, fmt=*) (olap%Eig(ib,it), ib=1,nb)
      read(unit=33, fmt='(*(f15.9))') &
        ((olap%Dij(ib,jb,it), jb=1,nb), ib=1,nb)
      read(unit=34, fmt='(*(f15.9))') &
        (( olap%EPcoup(ib,jb,1,1,it), jb=1,nb ), ib=1,nb)
    end do

    close(unit=32)
    close(unit=33)
    close(unit=34)

  end subroutine


end module epcoup
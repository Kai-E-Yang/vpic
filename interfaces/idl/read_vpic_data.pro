;------------------------------------------------------------------------
; IDL routine to read in field data at a given time point from 
; single- or multi-processor vpic-3 runs. 
;
; two user functions intended:  load_field_array, load_hydro_array
;
; arguments passed to function load_field_array: topology
; arguments passed to function load_hydro_array: topology
; dialog_pickfile() is used to obtain the data file (choose any one of
; the data files generated by vpic for a given time interval)
;
; topology = 0, 1, 2 to indicate || domain sliced in x, y, z directions. 
; return data is a struct of the form: 
;   { xmesh:xpoints, 
;     ymesh:ypoints, 
;     zmesh:zpoints, 
;     data:master_field_array }
; where xmesh, ymesh, zmesh are 1d arrays of the various meshes, 
; master_field_array is a 3D array of field_data structs (see below for 
; fields)
;
; Example IDL usage to make an Ex vs. x plot: 
;   d = load_field_array(0)
;   plot, d.xmesh, d.data.ex
;
; TODO:
;   - Still need to finish writing the particle load.
;   - Fix bug with the zmesh generation part of the generic load. 
;
;------------------------------------------------------------------------
; written by B. Albright, X-1, LANL  1/2005
;------------------------------------------------------------------------

forward_function load_field_array, load_hydro_array, load_generic_mesh_data

;========================================================================
; a do-nothing procedure to make sure that IDL loads this file when we 
; wish to read in data from the simulations. 
;
pro read_vpic_data
end


;========================================================================
; obtain hydro array data from single- or multi-processor vpic-3 run
;
function load_hydro_array, topology
  hydrostruct = { jx:0.0,  $  ; Current density        => < q v_i f >
		  jy:0.0,  $  
		  jz:0.0,  $  
		  rho:0.0, $  ; Charge density         => < q f > 
		  px:0.0,  $  ; Momentum density       => < p_i f > 
		  py:0.0,  $
		  pz:0.0,  $
		  ke:0.0,  $  ; Kinetic energy density => < m c^2 (gamma-1) f > 
		  txx:0.0, $  ; Stress diagonal        => < p_i v_j f >, i==j
		  tyy:0.0, $
		  tzz:0.0, $
		  tyz:0.0, $  ; Stress off-diagonal    => < p_i v_j f >, i!=j
		  tzx:0.0, $
		  txy:0.0, $
		  pad0:0.0,$  ; 16-byte align the structure
		  pad1:0.0 }
; FIXME: CELL W/ SPU ALIGNMENT ISSUES?
  return, load_generic_mesh_data(topology, hydrostruct, '*hydro*')
end


;========================================================================
; obtain field array data from single- or multi-processor vpic-3 run
;
function load_field_array, topology
  fieldstruct = { ex:0.0,      $
		  ey:0.0,      $
		  ez:0.0,      $
		  div_e_err:0.0, $
		  cbx:0.0,     $
		  cby:0.0,     $
		  cbz:0.0,     $
		  div_b_err:0.0, $
		  tcax:0.0,    $
		  tcay:0.0,    $
		  tcaz:0.0,    $
		  rhob:0.0,    $
		  jfx:0.0,     $
		  jfy:0.0,     $
		  jfz:0.0,     $
		  rhof:0.0,    $
		  ematx:0,     $
		  ematy:0,     $
		  ematz:0,     $
		  nmat:0,      $
		  fmatx:0,     $
		  fmaty:0,     $
		  fmatz:0,     $
		  cmat:0 }
; FIXME: CELL W/ SPU ALIGNMENT ISSUES?
  return, load_generic_mesh_data(topology, fieldstruct, 'fields*')
end


;========================================================================
; load generic data of form load_struct.  
;
; TODO: add some form of automatic topology detection & allow brick 
; toplogies
;
; topology = 0 implies sliced in x direction
; topology = 1 implies sliced in y direction
; topology = 2 implies sliced in z direction
;
function load_generic_mesh_data, topology, load_struct, filterval
  ; 
  ; pick any field file in list at given time step
  ; 
  filename_src = dialog_pickfile(/read, filter = filterval)
  parts = str_sep(filename_src, '.')
  filename_base = parts[0]
  for elem = 1, n_elements(parts) - 2 do begin
    filename_base = filename_base + '.' + parts[elem]
  endfor
  numfiles = n_elements(findfile(filename_base + '.' + '*'))
  ; now we wish to make a master array into which all the data will be read. 
  ; in general, this requires knowing how big all of the files are going 
  ; to be; however, vpic-3 allows different processors to have different 
  ; size arrays, so the only way I know how to do this is to do two 
  ; openings of the files--the first to determine the size of the 
  ; array; the second, to fill the arrays with the data. 
  ;------------------------------------------------------------------------
  ; V0 header block template
  ;
  v0struct = { version:0L, $
	       type:0L,    $
	       nt:0L,      $ 
	       nx:0L,      $
	       ny:0L,      $
	       nz:0L,      $
	       dt:0.0,     $
	       dx:0.0,     $
	       dy:0.0,     $
	       dz:0.0,     $
	       x0:0.0,     $
	       y0:0.0,     $
	       z0:0.0,     $
	       cvac:0.0,   $
	       eps0:0.0,   $
	       damp:0.0,   $
	       rank:0L,    $
	       ndom:0L,    $
	       spid:0L,    $
	       spqm:0.0 }
  itype = 0L
  ndim = 0L
  num_cells_in_subdivided_direction = 0L
  for ifile = 0, numfiles - 1 do begin
    filename = filename_base + '.' + strtrim(string(ifile),2)
    print, "parsing filename ", filename, " for array size information...."
    openr, lun, filename, /get_lun
    parse_boilerplate, lun
    readu, lun, v0struct
    readu, lun, itype
    readu, lun, ndim
    arraydimensions = LonArr(ndim)
    readu, lun, arraydimensions
    num_cells_in_subdivided_direction = $
      num_cells_in_subdivided_direction + arraydimensions[topology] - 2
    close, lun
    free_lun, lun
  endfor
  master_array_dim = arraydimensions - 2
  master_array_dim[topology] = num_cells_in_subdivided_direction
  print, "Total array dimensions: ", master_array_dim
  master_field_array = $
    reform(replicate(load_struct, $
		     master_array_dim[0] * master_array_dim[1] * master_array_dim[2]), $
	   master_array_dim)
  ;
  ; now that master_field_array is properly defined, read in the data
  ;
  nx_start = 0L
  ny_start = 0L
  nz_start = 0L
  for ifile = 0, numfiles - 1 do begin
    filename = filename_base + '.' + strtrim(string(ifile),2)
    print, "Parsing file ", filename, " for field data...."
    openr, lun, filename, /get_lun
    parse_boilerplate, lun
    readu, lun, v0struct
    readu, lun, itype
    readu, lun, ndim
    arraydimensions = LonArr(ndim)
    readu, lun, arraydimensions
    product_arraydimensions = arraydimensions[0] * arraydimensions[1] * arraydimensions[2]
    ;
    ; generate the meshpoints
    ;
    if (ifile eq 0) then begin
      xpoints = findgen(arraydimensions[0]-2) * v0struct.dx + v0struct.x0
      ypoints = findgen(arraydimensions[1]-2) * v0struct.dy + v0struct.y0
      zpoints = findgen(arraydimensions[2]-2) * v0struct.dz + v0struct.z0
    endif else begin
      case topology of 
        0: xpoints = [xpoints, $
                      (findgen(arraydimensions[0]-2) * v0struct.dx + v0struct.x0)]
        1: ypoints = [ypoints, $
                      (findgen(arraydimensions[1]-2) * v0struct.dy + v0struct.y0)]
        2: zpoints = [zpoints, $
                      (findgen(arraydimensions[2]-2) * v0struct.dz + v0struct.z0)]
        else: print, "Error: bad topology."
      endcase
    endelse
    ; 
    ; read the data
    ; TODO: more thoroughly test that there are no issues with alignment at array bounds. 
    ; 
    fieldarray_raw = replicate(load_struct, product_arraydimensions)
    readu, lun, fieldarray_raw
    master_field_array[nx_start:nx_start + (arraydimensions[0]-3), $
                       ny_start:ny_start + (arraydimensions[1]-3), $
                       nz_start:nz_start + (arraydimensions[2]-3)] = $
	(reform(fieldarray_raw, arraydimensions))[1:(arraydimensions[0]-2), $
						  1:(arraydimensions[1]-2), $
						  1:(arraydimensions[2]-2)]
    close, lun
    free_lun, lun
    case topology of 
      0: nx_start = nx_start + v0struct.nx
      1: ny_start = ny_start + v0struct.ny
      2: nz_start = nz_start + v0struct.nz
    endcase
  endfor
  data_struct = {xmesh:xpoints, ymesh:ypoints, zmesh:zpoints, data:master_field_array}
  return, data_struct
end


;========================================================================
; boilerplate: takes care of consistency binary header stuff Kevin put into 
; his V0 binary dumps
;
pro parse_boilerplate, lun
  sizearr = BytArr(5)
  readu, lun, sizearr
  cafevar = 0
  readu, lun, cafevar
  deadbeefvar = 0L
  readu, lun, deadbeefvar
  realone = 0.0
  readu, lun, realone
  doubleone = 0.0D
  readu, lun, doubleone
  ;
  ; If we have problems with data alignment on the read, uncomment print
  ; to make sure that each gives what we would expect: 
  ; print, cafevar, deadbeefvar, realone, doubleone
  ;
end






;========================================================================
; obtain particle data - 
;
;
;
; !!!!!incomplete!!!!! -- haven't redone it for the
; new script--just have copied over some stuff from an earlier single-proc. 
; IDL script I'd written: 
;


;------------------------------------------------------------------------
; I believe that this macro is how Kevin writes the index data for the particles: 
; 
; #define INDEX_FORTRAN_3(x,y,z,xl,xh,yl,yh,zl,zh) \
;  ((x)-(xl) + ((xh)-(xl)+1)*((y)-(yl) + ((yh)-(yl)+1)*((z)-(zl))))
;
; as demonstrated from this line in misc.cxx:
;
; vpic/misc.cxx:  
;   pi.i  = INDEX_FORTRAN_3(ix,iy,iz,0,grid->nx+1,0,grid->ny+1,0,grid->nz+1);
; 
; for the postproc, we need to extract the index data and use it to reconstruct 
; the physical particle position. 
;
; setting xl = yl = zl = 0
;  ix + (xh + 1)*(iy + (yh + 1)*iz)
; now setting xh = nx + 1, yh = ny + 1, zh = nz + 1: 
;  ix + (nx + 2)*(iy + (ny + 2)*iz)
; this is the index.  Now we need to do arithmetic to extract the ix, iy, iz: 
;   index = ix + (nx + 2) * iy + (nx + 2) * (ny + 2) * iz
;  
; integer arithmetic: 
; ------------------
; iz = index / ((nx + 2) * (ny + 2))     
; iy = (index - iz * ((nx + 2) * (ny + 2))) / (nx + 2)
; ix = index - ((nx + 2) * iy + (nx + 2) * (ny + 2) * iz)
; 
; nx, ny, nz are given in the v0 header struct, as are x0, y0, z0, dx, dy, dz: 
;
;   x position: x = x0 + ix * v0struct.dx + particlestruct.dx
;
; and similarly for y, z positions.  
;

function extract_particle_data, topology
  filename_src = dialog_pickfile(/read, filter = '*particle*')
  parts = str_sep(filename_src, '.')
  filename_base = parts[0]
  for elem = 1, n_elements(parts) - 2 do begin
    filename_base = filename_base + '.' + parts[elem]
  endfor
  numfiles = n_elements(findfile(filename_base + '.' + '*'))
  ;------------------------------------------------------------------------
  ; V0 header block template
  ;
  v0struct = { version:0L, $
	       type:0L,    $
	       nt:0L,      $ 
	       nx:0L,      $
	       ny:0L,      $
	       nz:0L,      $
	       dt:0.0,     $
	       dx:0.0,     $
	       dy:0.0,     $
	       dz:0.0,     $
	       x0:0.0,     $
	       y0:0.0,     $
	       z0:0.0,     $
	       cvac:0.0,   $
	       eps0:0.0,   $
	       damp:0.0,   $
	       rank:0L,    $
	       ndom:0L,    $
	       spid:0L,    $
	       spqm:0.0 }
  itype = 0L
  ndim = 0L
  num_particles_total = 0L
  num_particles_buf = 0L
  for ifile = 0, numfiles - 1 do begin
    filename = filename_base + '.' + strtrim(string(ifile),2)
    print, "parsing filename ", filename, " for array size information...."
    openr, lun, filename, /get_lun
    parse_boilerplate, lun
    readu, lun, v0struct
    readu, lun, itype
    readu, lun, ndim
    arraydimensions = LonArr(ndim)
    readu, lun, arraydimensions
    num_particles_total = $
      num_particles_total + arraydimensions[0]
    if (arraydimensions[0] gt num_particles_buf) then $
      num_particles_buf = arraydimensions[0]
    close, lun
    free_lun, lun
  endfor

  ;------------------------------------------------------------------------
  ; generate master particle array
  ;
  particle_struct = { dx:0.0, $  ; particle position in cell coordinates
                      dy:0.0,  $  
                      dz:0.0,  $  
                      i:0L, $   ; index of cell containing the particle 
                      ux:0.0,  $ ; particle normalized momentum
                      uy:0.0,  $  
                      uz:0.0,  $
                      q:0.0  $  ; particle charge
                   }
  print, "Particle array size: ", num_particles_total
  master_particle_array = replicate(particle_struct, num_particles_total)
  particle_read_buf = replicate(particle_struct, num_particles_buf)
  num_particles = 0L
  ;------------------------------------------------------------------------
  ; read particle data
  for ifile = 0, numfiles - 1 do begin
    filename = filename_base + '.' + strtrim(string(ifile),2)
    print, "parsing filename ", filename, " for particle data...."
    openr, lun, filename, /get_lun
    parse_boilerplate, lun
    readu, lun, v0struct
    readu, lun, itype
    readu, lun, ndim
    arraydimensions = LonArr(ndim)
    readu, lun, arraydimensions
    readu, lun, particle_read_buf[0:arraydimensions[0]-1]
    
    ;************************************************************************
    ; set dx, dy, dz to be the real x, y, z of the particles using the algorithm below. 
    ;************************************************************************

    ; now assign particle_read_buf to the proper place in the master_particle_array
    master_particle_array[num_particles:num_particles + arraydimensions[0] - 1] = $
      particle_read_buf[0:arraydimensions[0]-1]
    num_particles = $
      num_particles + arraydimensions[0]
    close, lun
    free_lun, lun
  endfor
  data_struct = {data:master_particle_array}
  return, data_struct
end

  


;  filename = dialog_pickfile(/read, filter = '*particle*')
;  openr, lun, filename, /get_lun
;  v0struct = read_v0(lun)
;  arraystruct = read_array_header(lun)
;  product_arraydimensions = $
;    arraystruct.arraydimensions[0] * arraystruct.arraydimensions[1] * arraystruct.arraydimensions[2]
;  ;------------------------------------------------------------------------
;  ; set up x array for plotting
;  ;
;  xpoints = (findgen(arraystruct.arraydimensions[0]-2) * v0struct.dx + v0struct.x0) * 1.e6 ; microns
;  ;------------------------------------------------------------------------
;  ; read the fields.  first replicate the array of field structs, and
;  ; then read the fields in. 
;  ;
;  particlestruct = { dx:0.0, $  ; particle position in cell coordinates
;                     dy:0.0,  $  
;                     dz:0.0,  $  
;                     i:0L, $    ; index of cell containing the particle 
;                     ux:0.0,  $ ; particle normalized momentum
;                     uy:0.0,  $  
;                     uz:0.0,  $
;                     q:0.0  $  ; particle charge
;                   }
;  ; debug: work with smaller array of particles until we get reader working right
;  ; particlearray = replicate(particlestruct, product_arraydimensions)
;  ; readu, lun, particlearray
;  ; 
;  ; begin debug: ---v
;  particlearraytmp = replicate(particlestruct, product_arraydimensions)
;  readu, lun, particlearraytmp
;  particlearray = particlearraytmp[0:100]
;  ; end debug:   ---^
;  print, particlearray
;  ; 
;  ;------------------------------------------------------------------------
;  ; extract the particle dx, i, ux, and q arrays
;  ;
;  nx_plus_2 = v0struct.nx + 2
;  ny_plus_2 = v0struct.ny + 2
;  dxarray = reform(particlearray.dx,arraystruct.arraydimensions)
;  iarray  = reform(particlearray.i,arraystruct.arraydimensions)
;  izarray = iarray / (nx_plus_2 * ny_plus_2)
;  iyarray = (iarray - izarray * nx_plus_2 * ny_plus_2) / nx_plus_2
;  ixarray = iarray - nx_plus_2 * (iyarray + ny_plus_2 * nzarray)
;  xarray  = v0struct.x0 + ixarray * v0struct.dx + dxarray
;  uxarray = reform(particlearray.ux,arraystruct.arraydimensions)
;  qarray  = reform(particlearray.q,arraystruct.arraydimensions)
;  return, {xarray:xpoints, xarray:xarray, uxarray:uxarray, qarray:qarray}
;end ; extract_particle_data
;
;
;
;
;


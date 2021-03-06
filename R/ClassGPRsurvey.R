
#------------------------------------------#
#----------- CLASS DEFINITION -------------#
setClass(
  Class="GPRsurvey",  
  slots=c(
    version = "character",     # version of the class
    filepaths = "character",     # filepath of the GPR data
    names = "character",      # names of the GPR profiles
    descriptions = "character",  # descriptions of the GPR profiles
    freqs = "numeric",       # frequencies of the GPR profiles
    lengths = "numeric",      # length in metres of the GPR profiles = [n]
    surveymodes ="character",  # survey mode (reflection/CMP)
    dates ="character",      # dates  of the GPR profiles
    antseps ="numeric",      # antenna separation of the GPR profiles
    posunit = "character",    # position units 
    crs ="character",      # coordinates reference system
    coordref="numeric",      # reference position
    coords="list",        # (x,y,z) coordinates for each profiles
    intersections="list",    # (x,y) position of the profile intersections
    fids="list"          # fiducials of the GPR profiles
  )
)

#------------------------------------------#
#-------------- CONSTRUCTOR ---------------#
#' Create an object of the class GPRsurvey
#'
#' Create an object of the class GPRsurvey using a vector of GPR data filepath
#' @name GPRsurvey
#' @export
# LINES = list of datapath
GPRsurvey <- function(LINES){
  n <- length(LINES)
  line_names <- character(n)
  line_descriptions <- character(n)
  line_surveymodes <- character(n)
  line_dates <- character(n)
  line_freq <- numeric(n)
  line_antsep <- numeric(n)
  line_lengths <- numeric(n)
  posunit <- character(n)
  crs <- character(n)
  xyzCoords <- list()
  fids <- list()
  for(i in seq_along(LINES)){
    gpr <- readGPR(LINES[[i]])
    # FIX ME!
    #  > check if name(gpr) is unique
    line_names[i]        <- name(gpr)[1]
    line_descriptions[i] <- description(gpr)
    line_surveymodes[i]  <- gpr@surveymode
    if(length(gpr@date) == 0){
      line_dates[i]        <- NA
    }else{
      line_dates[i]        <- gpr@date
    }
    if(length(gpr@freq) == 0){
      line_freq[i]        <- NA
    }else{
      line_freq[i]        <- gpr@freq
    }
    if(length(gpr@antsep) == 0){
      line_antsep[i]        <- NA
    }else{
      line_antsep[i]        <- gpr@antsep
    }
    posunit[i]           <- gpr@posunit[1]
    crs[i] <- ifelse(length(gpr@crs) > 0, gpr@crs[1], character(1))
    if(length(gpr@coord)>0){
      if(is.null(colnames(gpr@coord))){
        xyzCoords[[line_names[i] ]] <- gpr@coord
      }else if(all(toupper(colnames(gpr@coord)) %in% c("E","N","Z"))){
        xyzCoords[[line_names[i] ]] <- gpr@coord[,c("E","N","Z")]
      }else if(all(toupper(colnames(gpr@coord)) %in% c("X","Y","Z"))){
        xyzCoords[[line_names[i] ]] <- gpr@coord[,c("X","Y","Z")]
      }else{
        xyzCoords[[line_names[i] ]] <- gpr@coord
      }
      line_lengths[i]      <- posLine(gpr@coord[,1:2],last=TRUE)
    }else{
      line_lengths[i]    <- gpr@dx * ncol(gpr@data)
    }
    fids[[line_names[i] ]]    <- trimStr(gpr@fid)
  }
  if(length(unique(posunit)) == 1){
    posunit <- posunit[1]  
    if(posunit == "") posunit <- character(0)
  }else{
    stop("Unit positions are not the same: \n",
         paste0(unique(posunit), collaspe = ", "),
         "!!\n")
  }
  if(length(unique(crs)) == 1){
    crs <- crs[1]  
    if(crs == "") crs <- character(0)
  }else{
    crs <- names(which.max(table(crs))[1])
    warning("Not all the coordinate reference systems are identical!",
            "I take ", crs , "!\n")
  }
  x <- new("GPRsurvey",
        version     = "0.1",
        filepaths    = LINES,       # vector of [n] file names
        names      = line_names,      # length = [n]
        descriptions   = line_descriptions,  # length = [n]
        surveymodes   = line_surveymodes,    # length = [n]
        dates       = line_dates,      # length = [n]
        freqs       = line_freq,       # length = [n]
        lengths     = line_lengths,       # length = [n]
        antseps     = line_antsep,      # length = [n]
        posunit     = posunit,    # length = 1
        crs       = crs,      # length = 1
        coords      = xyzCoords,    # header
        fids      = fids,
        intersections  = list()
  )
  x <- coordref(x)
  return(x)
}

#' @export
setAs(from = "GPRsurvey", to = "SpatialLines",
      def = function (from) as.SpatialLines(from))
      
#' @export
setAs(from = "GPRsurvey", to = "SpatialPoints",
      def = function (from) as.SpatialPoints(from))    

#' Coerce to SpatialLines
#'
#' @name GPRsurvey.as.SpatialLines
#' @rdname GPRsurveycoercion
#' @export
setMethod("as.SpatialLines", signature(x = "GPRsurvey"), function(x){
  # remove NULL from list
  isNotNull <- !sapply(x@coords, is.null)
  if(any(isNotNull)){
    xyz <- x@coords[isNotNull]
    lineList <- lapply(xyz, xyToLine)
    linesList <- lapply(seq_along(lineList), LineToLines, lineList, 
                        names(xyz))
    mySpatLines <- sp::SpatialLines(linesList)
    if(length(x@crs) == 0){
      warning("no CRS defined!\n")
    }else{
      sp::proj4string(mySpatLines) <- sp::CRS(crs(x))
    }
    return(mySpatLines)
  }else{
    warning("no coordinates!")
    return(NULL)   
  }
})

#' Coerce to SpatialPoints
#'
#' @name GPRsurvey.as.SpatialPoints
#' @rdname GPRsurveycoercion
#' @export
setMethod("as.SpatialPoints", signature(x = "GPRsurvey"), function(x){
  allTopo <- do.call(rbind, x@coords)  #  N, E, Z
  allTopo2 <- as.data.frame(allTopo)
  names(allTopo2) <- c("E", "N", "Z")
  sp::coordinates(allTopo2) <- ~ E + N
  if(length(x@crs) == 0){
    warning("no CRS defined!\n")
  }else{
    sp::proj4string(allTopo2) <- sp::CRS(crs(x))
  }
  return(allTopo2)
})

#' Define a local reference coordinate
#' 
#' @rdname coordref-methods
#' @aliases coordref,GPRsurvey-method
setMethod("coordref", "GPRsurvey", function(x){
    if(length(x@coords) > 0){
      A <- do.call("rbind", x@coords)
      A <- apply(round(A),2,range)
      Evalue <- .minCommon10(A[1,1],A[2,1])
      Nvalue <- .minCommon10(A[1,2],A[2,2])
      Zvalue <- 0
      x@coordref <- c(Evalue, Nvalue,Zvalue)
      cat("Coordinates of the local system:", x@coordref,"\n")
      x <- surveyIntersect(x)
    }
    return(x)
  }
)

setReplaceMethod(
  f="coordref",
  signature="GPRsurvey",
  definition=function(x,value){
    x@coordref <- value
    return(x)
  }
)

#' @name crs
#' @rdname crs
#' @export
setMethod("crs", "GPRsurvey", function(x){
    return(x@crs)
  } 
)


#' @name crs
#' @rdname crs
#' @export
setReplaceMethod(
  f="crs",
  signature="GPRsurvey",
  definition=function(x,value){
    value <- as.character(value)[1]
    x@crs <- value
    return(x)
  }
)

#------------------------------
# "["
#' extract parts of GPRsurvey
#'
#' Return an object of class GPRsurvey
#' @name GPRsurvey-subset
#' @docType methods
#' @rdname GPRsurvey-subset
setMethod(
  f= "[",
  signature="GPRsurvey",
  definition=function(x,i,j,drop){
    if(missing(i)) i <- j
    # cat(typeof(i),"\n")
    # cat(j,"\n")
    # i <- as.numeric(i)
    y <- x
    y@filepaths      <- x@filepaths[i]
    y@names          <- x@names[i]
    y@descriptions   <- x@descriptions[i]
    y@surveymodes    <- x@surveymodes[i]
    y@dates          <- x@dates[i]
    y@freqs          <- x@freqs[i]
    y@lengths        <- x@lengths[i]
    y@antseps        <- x@antseps[i]
    y@crs            <- x@crs
    y@coords         <- x@coords[x@names[i]]
    y@fids           <- x@fids[x@names[i]]
    y@intersections  <- x@intersections[x@names[i]]
    return(y)
  }
)

#------------------------------

# "[["
# return an instance of the class GPR!
# identical to getGPR
# i can be either the gpr data number or the gpr data name

#' extract a GPR object from a GPRsurvey object
#'
#' Return an object of class GPR
#' @name [[
#' @docType methods
#' @rdname GPRsurvey-subsubset
setMethod(
  f= "[[",
  signature="GPRsurvey",
  definition=function (x, i, j, ...){
    if(missing(i)) i <- j
    return(getGPR(x, id = i))
  }
)
    
#-------------------------------
#' @rdname GPRsurvey-subsubset
setReplaceMethod(
  f = "[[",
  signature = "GPRsurvey",
  definition = function(x, i, value){
    if(class(value) != "GPR"){
      stop("'value' must be of class 'GPR'!")
    }
    if(missing(i)){
      stop("missing index")  
    }
    i <- as.integer(i[1])
    oldName <- x@names[i]
    newName <- value@name
    ng <- x@names[-i]
    it <- 1
    while(newName %in% ng){
      newName <- paste0(value@name, "_", it)
      it <- it + 1
    }
    #tmpf <- tempfile(newName)
    value@name <- newName
    #writeGPR(value, type = "rds", overwrite = FALSE,
    #       fPath = tmpf)
    x@names[i] <- newName
    # x@filepaths[[i]] <- paste0(tmpf, ".rds")
    x@filepaths[[i]] <- .saveTempFile(value)
    x@descriptions[i] <- value@description
    x@freqs[i] <- value@freq
    x@lengths[i] <- posLine(value@coord[,1:2], last = TRUE)
    x@surveymodes[i] <- value@surveymode
    x@dates[i] <-  value@date
    x@antseps[i] <- value@antsep
    if(length(x@coords) > 0){
      x@coords[[oldName]] <- value@coord
      names(x@coords)[i] <- newName
    }else if(length(value@coord) > 0){
      x@coords <- vector(mode = "list", length = length(x))
      x@coords[[i]] <- value@coord
      names(x@coords) <- x@names
    }
    if(length(x@fids) > 0){
      x@fids[[oldName]] <- value@fid
      names(x@fids)[i] <- newName
    }else if(length(value@fid) > 0){
      x@fids <- vector(mode = "list", length = length(x))
      x@fids[[i]] <- value@fid
      names(x@fids) <- x@names
    }
    x@intersections <- list()
    x <- coordref(x)
    return (x)
  }
)

#' Extract GPR object from GPRsurvey object
#' 
#' Extract GPR object from GPRsurvey object
#' @rdname getGPR
#' @export
setMethod("getGPR", "GPRsurvey", function(x,id){
    if(length(id)>1){
      warning("Length of id > 1, I take only the first element!\n")
      id <- id[1]
    }
    if(is.numeric(id)){
      gpr <- readGPR(x@filepaths[[id]])
    }else if(is.character(id)){
      no <- which(x@names == trimStr(id))
      if(length(no > 0)){
        gpr <- readGPR(x@filepaths[[no]])
      }else{
        stop("There is no GPR lines with name '", trimStr(id),"'\n")
      }
    }
    if(length(x@coords[[gpr@name]])>0){
      gpr@coord <- x@coords[[gpr@name]]
    }
    if(length(x@intersections[[gpr@name]])>0){
      #ann(gpr) <- x@intersections[[gpr@name]][,3:4,drop=FALSE]
      ann(gpr) <- cbind(x@intersections[[gpr@name]]$trace,
                        x@intersections[[gpr@name]]$name)
    }
    if(length(x@coordref)>0){
      gpr@coordref <- x@coordref
    }
    return(gpr)
  }
)



#-------------------------------------------#
#---------------- SETMETHOD ----------------#
#' Print GPR survey
#'
#' @method print GPRsurvey
#' @name print
#' @rdname show
# > 2. S3 function:
# setMethod("print", "GPR", function(x) print.GPR(x))   
# > 2. S3 function:
print.GPRsurvey <- function(x, ...){
  cat("*** Class GPRsurvey ***\n")
  n <- length(x)
  dirNames <- dirname(x@filepaths)
  if(length(unique(dirNames))==1){
    cat("Unique directory:", dirNames[1],"\n")
  }else{
    cat("One directory among others:", dirNames[1],"\n")
  }
  testCoords <- rep(0, n)
  names(testCoords) <- x@names
  if(length(x@coords) > 0){
    testLength <- sapply(x@coords, length)
    testCoords[names(testLength)] <- testLength
  }
  testCoords <- as.numeric(testCoords > 0)+1
  testIntersecs <- rep(0,n)
  names(testIntersecs) <- x@names
  if(length(x@intersections)>0){
    testLength <- sapply(x@intersections,length)
    testIntersecs[names(testLength)] <- testLength
  }
  testIntersecs <- as.numeric(testIntersecs > 0)+1
  
  is_test <- c("NO","YES")
  cat("- - - - - - - - - - - - - - -\n")
  #overview <- data.frame("name" = .fNameWExt(x@filepaths),
  overview <- data.frame("name" = x@names,
              "length" = round(x@lengths,2),
              "units" = rep(x@posunit, n),
              "date" = x@dates,
              "freq" = x@freqs,
              "coord" = is_test[testCoords],
              "int" = is_test[testIntersecs],
              "filename" = basename(x@filepaths))
  print(overview)
  if(length(x@coords)>0 ){
    cat("- - - - - - - - - - - - - - -\n")
    if(length(x@crs) > 0 ){
      cat("Coordinate system:", x@crs,"\n")
    }else{
      cat("Coordinate system: undefined\n")
    }
    cat
  }
  cat("****************\n")
  return(invisible(overview))
}

#' Show some information on the GPR object
#'
#' Identical to print().
#' @name show
#' @rdname show
# > 3. And finally a call to setMethod():
setMethod("show", "GPRsurvey", function(object){print.GPRsurvey(object)}) 


# setMethod("length", "GPRsurvey", function(x) ncol(x@data))

#' @export
setMethod(f="length", signature="GPRsurvey", definition=function(x){
    length(x@filepaths)
  }
)

# parameter add=TRUE/FALSE
#       addArrows = TRUE/FALSE
#' Plot the GPRsurvey object.
#'
#' Plot GPR suvey lines
#' @method plot GPRsurvey 
#' @name plot
#' @rdname plot
#' @export
plot.GPRsurvey <- function(x, y, ...){
  if(length(x@coords) > 0){
    #isNotNull <- which(!sapply(x@coords, is.null))
    #x <- x[isNotNull]
    add <- FALSE
    add_shp_files <- FALSE
    parArrows <- list(col = "red", length = 0.1)
    parIntersect <- list(pch=1,cex=0.8)
    parFid <- list(pch=21,col="black",bg="red",cex=0.7)
    xlab <- "E"
    ylab <- "N"
    main <- ""
    asp <- 1
    lwd <- 1
    col <- 1
    # print(list(...))
    dots <- list()
    if( length(list(...)) > 0 ){
      dots <- list(...)
      uN <- table(names(dots))
      if(any(uN > 1)){
        idx <- which(uN > 1)
        stop("Arguments '", names(uN[idx]), "' is not unique!")  
      }
      if( !is.null(dots$add) && isTRUE(dots$add) ){
        add <- TRUE
      }
      if(!is.null(dots$main)){
        main <- dots$main
        dots$main <- NULL
      }
      if(!is.null(dots$xlab)){
        xlab <- dots$xlab
        dots$xlab <- NULL
      }
      if(!is.null(dots$ylab)){
        ylab <- dots$ylab
        dots$ylab <- NULL
      }
      if(!is.null(dots$asp)){
        asp <- dots$asp
        dots$asp <- NULL
      }
      if(!is.null(dots$col)){
        col <- dots$col
      }
      if("parArrows" %in% names(dots)){
      #if(!is.null(dots$lwd)){
        parArrows <- dots$parArrows
        dots$parArrows <- NULL
      }
      if("parIntersect" %in% names(dots)){
      #if(!is.null(dots$parIntersect)){
        parIntersect <- dots$parIntersect
        dots$parIntersect <- NULL
      }
      if("parFid" %in% names(dots)){
        parFid <- dots$parFid
        dots$parFid <- NULL
      }
      if(!is.null(dots$addFid)){
        stop(paste0("'addFid' no more used! Use instead 'parFid'",
                      " with a vector of arguments for the points",
                      "function.\n"))
      }
      # dots$addFid <- NULL
      # dots$add <- NULL
      if(!is.null(dots$shp_files)){
        add_shp_files <- TRUE
        shp_files <- dots$shp_files
      }
      dots$shp_files <- NULL
    }
    #dots <- c(dots, list(type = "n",
    #                     xlab = xlab,
    #                     ylab = ylab))
    # print(dots)
    if(!add){
      xlim <- c(min(sapply(x@coords, function(y) min(y[,1]))),
                max(sapply(x@coords, function(y) max(y[,1]))))
      ylim <- c(min(sapply(x@coords, function(y) min(y[,2]))),
                max(sapply(x@coords, function(y) max(y[,2]))))
      #do.call("plot", c(list((do.call(rbind, x@coords))[,1:2]), dots))
      plot(0,0, type = "n", xlim = xlim, ylim = ylim, xlab = xlab,
                         ylab = ylab, main = main, asp = asp)
    }
    if(add_shp_files){
      if(length(shp_files) > 0){
                sel <- seq(from=1,length.out=length(shp_files),by=2)
        BASEName <- unlist(strsplit(basename(shp_files),'[.]'), 
                           use.names = FALSE)[sel]
        DIRName <- dirname(shp_files)
        for(i in seq_along(shp_files)){
          shp <- rgdal::readOGR(DIRName[i], BASEName[i])
          message(DIRName[i], BASEName[i])
          plot(shp, add = TRUE,pch=13,col="darkblue")
        }
      }
    }
    for(i in 1:length(x)){
      if(is.null(x@coords[[x@names[i]]])){
        message(x@names[i], ": coordinates missing.")
      }else{
        xyz <- unname(x@coords[[x@names[i]]])
        dots$x <- xyz[,1]
        dots$y <- xyz[,2]
        do.call(graphics::lines, dots)
        if(!is.null(parArrows)){
         do.call(arrows, c(xyz[nrow(xyz)-1,1], xyz[nrow(xyz)-1,2], 
                           x1 = xyz[nrow(xyz),1],   y1 = xyz[nrow(xyz),2], 
                           parArrows))
        }
        if(!is.null(parFid)){
          fidxyz <- x@coords[[x@names[i]]][trimStr(x@fids[[i]]) != "", , 
                                  drop = FALSE]
          if(length(fidxyz)>0){
            do.call( graphics::points, c(list(x = fidxyz[, 1:2]), parFid))
          }
        }
      }
    }
    #niet <- lapply(x@coords, .plotLine, lwd = lwd, col = col )
    # if(!is.null(parArrows)){
    #   for(i in 1:length(x)){
    #     xyz <- unname(x@coords[[i]])
    #     do.call(arrows, c(xyz[nrow(xyz)-1,1], xyz[nrow(xyz)-1,2], 
    #                       x1 = xyz[nrow(xyz),1],   y1 = xyz[nrow(xyz),2], 
    #                       parArrows))
    #   }
    #   #niet <- lapply(x@coords, .plotArrows, parArrows)
    # }
    # if(!is.null(parFid)){
    #   for(i in 1:length(x)){
    #     fidxyz <- x@coords[[i]][trimStr(x@fids[[i]]) != "", , 
    #                                 drop = FALSE]
    #     if(length(fidxyz)>0){
    #       do.call( points, c(list(x = fidxyz[, 1:2]), parFid))
    #     }
    #   }
    # }
    if(!is.null(parIntersect) && length(x@intersections) > 0){ 
      for(i in 1:length(x@intersections)){
        if(!is.null(x@intersections[[i]])){
          do.call(points , c(list(x=x@intersections[[i]]$coord), 
                  parIntersect))
        }
      }
    }
  }else{
    stop("no coordinates")
  }
}

#' Plot the GPR survey as lines
#'
#' Plot the GPR survey as lines
#' @method lines GPRsurvey 
#' @name lines
#' @rdname lines
#' @export
lines.GPRsurvey <- function(x, ...){
  dots <- list(...)
  for(i in 1:length(x)){
    xy <- unname(x@coords[[i]][,1:2])
    dots$x <- xy[,1]
    dots$y <- xy[,2]
    do.call(lines, dots)
  }
}

# intersection
# list
#     $GPR_NAME
#         $ coords (x,y)
#         $ trace
#         $ name

#' Compute the survey intersections
#' 
#' Compute the survey intersections
#' @rdname surveyIntersect
#' @export
setMethod("surveyIntersect", "GPRsurvey", function(x){
  # intersections <- list()
  for(i in seq_along(x@coords)){
    if(!is.null(x@coords[[i]])){
      top0 <- x@coords[[i]]
      Sa <- suppressWarnings(as.SpatialLines(x[i]))
      v <- seq_along(x@coords)[-i]
      int_coords <- c()
      int_traces <- c()
      int_names <- c()
      for(j in seq_along(v)){
        if(!is.null(x@coords[[v[j]]])){
          top1 <- x@coords[[v[j]]]
          Sb <- suppressWarnings(as.SpatialLines(x[v[j]]))
          pt_int <- rgeos::gIntersection(Sa,Sb)
          if(!is.null(pt_int) && class(pt_int) == "SpatialPoints"){
            # for each intersection points
            for(k in seq_along(pt_int)){
              d <- sqrt(rowSums((top0[,1:2] - 
                              matrix(sp::coordinates(pt_int)[k,],
                              nrow = nrow(top0), ncol = 2, byrow = TRUE))^2))
              int_coords <- rbind(int_coords, sp::coordinates(pt_int)[k,])
              int_traces <- c(int_traces, which.min(d)[1])
              int_names  <- c(int_names, x@names[v[j]])
            }
          }
        }
      }
      if(length(int_names) > 0){
        x@intersections[[x@names[i]]] <- list(coord = int_coords,
                                              trace = int_traces,
                                              name  = int_names)
      }else{
        x@intersections[[x@names[i]]] <- NULL
      }
    }
  }
  return(x)
})

#' Return intersection from GPRsurvey
#'
#' @rdname intersections-methods
#' @aliases intersections,GPRsurvey-method
setMethod("intersections", "GPRsurvey", function(x){
    return(x@intersections)
  }
)

           
#' @export
setMethod("trRmDuplicates", "GPRsurvey", function(x, tol = NULL){
  nrm <- integer(length(x))
  for(i in seq_along(x)){
    y <- x[[i]]
    n0 <- ncol(y)
    y <- suppressMessages(trRmDuplicates(y))
    if( (n0 - ncol(y)) > 0){
      message(n0 - ncol(y), " duplicated trace(s) removed from '", name(y), "'!")
      x@filepaths[[i]]     <- .saveTempFile(y)
      x@coords[[y@name]]   <- y@coord
      x@fids[[y@name]]     <- y@fid
    }
  }
  x@intersections <- list()
  x <- coordref(x)
  return(x) 
})

#' @export
setMethod("interpPos", "GPRsurvey",
          function(x, topo, plot = FALSE, r = NULL, tol = NULL, 
                   method = c("linear", "spline", "pchip"), ...){
    for(i in seq_along(x)){
      gpr <- readGPR(x@filepaths[[i]])
      # topoLine <- topo[[i]]
      # gpr <- interpPos(gpr,topoLine, ...)
      gpr <- interpPos(gpr, topo[[i]], plot = plot, r = r, tol = tol, 
                       method = method, ...)
      x@coords[[gpr@name]] <- gpr@coord
      x@lengths[i] <- posLine(gpr@coord[ ,1:2], last = TRUE)
    }
    x@intersections <- list()
    x <- coordref(x)
    return(x)
  }
)

#' Reverse the trace position.
#'
#' @name reverse
#' @rdname reverse
#' @export
setMethod("reverse", "GPRsurvey", function(x, id = NULL, tol = 0.3){
  if(is.null(id) && length(x@coords) > 0){
    # reverse radargram based on their name 
    # (all the XLINE have the same orientation, 
    # all the YLINE have the same orientation)
    lnTypes <- gsub("[0-9]*$", "", basename(x@names))
    lnTypeUniq <- unique(lnTypes)
    angRef <- rep(NA, length = length(lnTypeUniq))
    # revTRUE <- rep(FALSE, length = length(x))
    for(i in seq_along(x)){
      y <- x[[i]]
      typeNo <- which(lnTypeUniq %in% lnTypes[[i]] )
      if(is.na(angRef[typeNo])){
        angRef[typeNo] <- gprAngle(y)
      }else{
        angi <- gprAngle(y) 
        if(!isTRUE(inBetAngle( angRef[typeNo], angi, atol = tol))){
          y <- reverse(y)
          # revTRUE[i] <- TRUE
          message(y@name, " > reverse!")
          # tmpf <- tempfile(y@name)
          # writeGPR(y, type = "rds", overwrite = FALSE, fPath = tmpf)
          # x@filepaths[[i]]     <- paste0(tmpf, ".rds")
          x@filepaths[[i]]     <- .saveTempFile(y)
          x@coords[[y@name]]   <- y@coord
          x@fids[[y@name]]      <- y@fid
        }
      }
    }
    x@intersections <- list()
    x <- coordref(x)
    return(x)
  }
  if (is.null(id) || (is.character(id) && id == "zigzag")){
    if(length(x) > 1){
      id <- seq(from = 2L, by = 2L, to = length(x))
    }
  } 
  if(is.numeric(id)){
    id <- as.integer(id)
    if(max(id) <= length(x) && min(id) >= 1){
      for(i in seq_along(id)){
        y <- getGPR(x, id = id[i])
        y <- reverse(y)
        x@filepaths[[id[i]]]     <- .saveTempFile(y)
        if(length(y@coord) > 0){
          # x@coords[[y@name]]   <- y@coord
          x@coords[[id[i]]]   <- y@coord
        }
        # x@fids[[y@name]]      <- y@fid
        x@fids[[id[i]]]      <- y@fid
      }
      x@intersections <- list()
      x <- coordref(x)
      return(x) 
    }else{
      stop("id must be between 1 and ", length(x),"!")
    }
  }
})


# value = x, y, dx, dy

#' Set grid coordinates the trace position.
#'
#' Set grid coordinates to a survey
#' @param x An object of the class GPRsurvey
#' @param value A list with following elements: \code{xlines} (number or id of 
#'              the GPR data along the x-coordinates), \code{ylines} (number or 
#'              id of the GPR data along the y-coordinates), \code{xpos} 
#'              (position of the x-GPR data on the x-axis),
#'              \code{xpos} (position of the y-GPR data on the y-axis)
#' @rdname setGridCoord-methods
#' @export
setReplaceMethod(
  f="setGridCoord",
  signature="GPRsurvey",
  definition=function(x, value){
    value$xlines <- unique(value$xlines)
    value$ylines <- unique(value$ylines)
    if( any(value$xlines %in% value$ylines) ){
      stop("No duplicates between 'x' and 'y' allowed!")
    }
    
    if(length(value$xlines) != length(value$xpos)){
      stop("length(x) must be equal to length(dx)")
    }
    if(length(value$ylines) != length(value$ypos)){
      stop("length(y) must be equal to length(dy)")
    }
    if(!is.null(value$xlines)){
      if(is.numeric(value$xlines)){
        if(max(value$xlines) > length(x) || 
           min(value$xlines) < 1){
          stop("Length of 'xlines' must be between 1 and ", length(x))
        }
        xNames <- x@names[value$xlines]
      }else if(is.character(value$xlines)){
        if(!all(value$xlines %in% x@names) ){
          stop("These names do not exist in the GPRsurvey object:\n",
               value$xlines[! (value$xlines %in% x@names) ])
        }
        xNames <- value$xlines
      }
      for(i in seq_along(xNames)){
        y <- getGPR(x, xNames[i])
        ntr <- ncol(y)
        x@coords[[xNames[i]]] <- matrix(0, nrow = ntr, ncol = 3)
        x@coords[[xNames[i]]][,1] <- value$xpos[i]
        x@coords[[xNames[i]]][,2] <- y@pos
      }
    }
    if(!is.null(value$ylines)){
      if(is.numeric(value$ylines)){
        if(max(value$ylines) > length(x) || 
           min(value$ylines) < 1){
          stop("Length of 'ylines' must be between 1 and ", length(x))
        }
        yNames <- x@names[value$ylines]
      }else if(is.character(value$ylines)){
        if(!all(value$ylines %in% x@names) ){
          stop("These names do not exist in the GPRsurvey object:\n",
               value$ylines[! (value$ylines %in% x@names) ])
        }
        xyNames <- value$ylines
      }
      for(i in seq_along(yNames)){
        y <- getGPR(x, xNames[i])
        ntr <- ncol(y)
        x@coords[[yNames[i]]] <- matrix(0, nrow = ntr, ncol = 3)
        x@coords[[yNames[i]]][,1] <- y@pos
        x@coords[[yNames[i]]][,2] <- value$ypos[i]
      }
    }
    return(x)
  }
)


#' Return coordinates
#'
#' Return coordinates
#' @rdname coords-methods
#' @aliases coords,GPRsurvey-method
setMethod(
  f="coords",
  signature="GPRsurvey",
  definition=function(x, i){
    if(length(x@coords) == 0){
      return(x@coords)
    }
    if(missing(i)){
      return(x@coords)
    }else{
      return(x@coords[[i]])
    }
  }
)

#' Set coordinates
#'
#' @rdname coords-methods
#' @aliases coords<-,GPRsurvey-method
setReplaceMethod(
  f = "coords",
  signature = "GPRsurvey",
  definition = function(x, value){
    if(!is.list(value)){
      stop("value should be a list!!\n")
    }
    if(length(value) != length(x)){
      stop("number of elements not equal to the number of gpr files!!\n")
    }
    for(i in seq_along(x)){
      if( nrow(value[[i]]) != ncol(x[[i]]) ){
        stop("error with the ", i, "th element of 'value':",
             " number of coordinates is different from number of traces")
      } 
      if(is.null(colnames(value[[i]]))){
        x@coords[[x@names[i]]] <- as.matrix(value[[i]])
      }else if(all(toupper(colnames(value[[i]])) %in% c("E","N","Z"))){
        x@coords[[x@names[i]]] <- as.matrix(value[[i]][c("E","N","Z")])
      }else{
        x@coords[[x@names[i]]] <- as.matrix(value[[i]])
      }
      x@lengths[i] <- posLine(value[[i]][,1:2],last=TRUE)
    }
    # in coordref, the intersection is computed by 
    #    "x <- surveyIntersect(x)"
    # remove duplicates
    x@intersections <- list()
    x <- trRmDuplicates(x, tol = NULL)
    #x <- coordref(x)
    return(x)
  }
)
    
# Rotate coordinates of the GPR traces
#
setMethod("georef", "GPRsurvey", 
          function(x, alpha = NULL, cloc = c(0,0), creg = NULL,
                   ploc = NULL, preg = NULL, FUN = mean){
  if(is.null(center)){
    center <- .centroid(x)
  }
  xyz  <- lapply(x@coords, georef, alpha = NULL, cloc = c(0,0), 
                 creg = NULL, ploc = NULL, preg = NULL, FUN = mean)
  #xyz2 <- lapply(x@intersections$coord, georef, alpha = NULL, cloc = c(0,0), 
  #               creg = NULL, ploc = NULL, preg = NULL, FUN = mean)
  x@coords <- xyz
  x@intersections <- list()
  x <- coordref(x)
  return(x)
})

.centroid <- function(x){
  pos <- do.call(rbind, x@coords)
  return(colMeans(pos))
}

#' @export
setMethod("shiftEst", "GPRsurvey", function(x, y = NULL, 
          method=c("phase", "WSSD"), dxy = NULL, ...){
  if(!is.null(dxy) && length(dxy) != 2){
    stop("dxy is either NULL or a length-two vector")
  }
  Dshift <- matrix(ncol = 2, nrow = length(x) - 1)
  y <- x[[1]]
  ny <- nrow(y)
  my <- ncol(y)
  i0 <- NULL
  j0 <- NULL
  if( length(list(...)) ){
    dots <- list(...)
    if( !is.null(dots$i)){
      i0 <- dots$i
    }
    if( !is.null(dots$j)){
      j0 <- dots$j
    }
  }
  for(k in seq_len(length(x)-1)){
    z <- x[[k + 1]]
    nz <- nrow(z)
    mz <- ncol(z)
    if(is.null(i0)){
      i <- seq_len(min(nz, ny))
    }else{
      i <- i0
    }
    if(is.null(j0)){
      j <- seq_len(min(mz, my))
    }else{
      j <- j0
    }
    Dshift[k,] <- displacement(y@data[i, j], z@data[i,j], 
                          method = "phase", dxy = dxy)
    y <- z
    ny <- nz
    my <- mz
  }

  return( Dshift )
})    
    
#' @export
setMethod("plot3DRGL", "GPRsurvey", 
        function(x, addTopo = FALSE, clip = NULL, normalize = NULL, 
                 nupspl=NULL, add = TRUE, xlim = NULL, ylim= NULL, 
                 zlim = NULL, ...){
    add <- add
    for(i in seq_along(x)){
      cat("***", i , "***\n")
      gpr <- readGPR(x@filepaths[[i]])
      if(length(x@coords[[gpr@name]])>0){
        gpr@coord <- x@coords[[gpr@name]]
        # cat(x@coordref,"\n")
        gpr@coordref <- x@coordref
      }
      if(length(coord(gpr))==0){
        message(gpr@name, ": no coordinates, I cannot plot",
                  " this line!!")
      }else{
        plot3DRGL(gpr, addTopo = addTopo, clip = clip, normalize = normalize, 
                  nupspl = nupspl, add = add, xlim = xlim, ylim = ylim, 
                  zlim = zlim, ...)
      }
      add <- TRUE
    }  
  }
)



#' @export
setMethod("plotDelineations3D", "GPRsurvey", 
          function(x,sel=NULL,col=NULL,add=TRUE,...){
    add<-add
    for(i in seq_along(x)){
      gpr <- readGPR(x@filepaths[[i]])
      if(length(x@coords[[gpr@name]])>0){
        gpr@coord <- x@coords[[gpr@name]]
        # cat(x@coordref,"\n")
        gpr@coordref <- x@coordref
      }
      if(length(coord(gpr))==0){
        message(gpr@name, ": no coordinates, I cannot plot",
                  " this line!!")
      }else if(length(gpr@delineations) == 0){
        message(gpr@name, ": no delineations for this line!!")
      }else{
        plotDelineations3D(gpr,sel=sel,col=col,add=add,...)
      }
      add <- TRUE
    }  
  }
)


#----------------------- EXPORT/SAVE -----------------#
#' Write GPRsurvey object
#' 
#' Write GPRsurvey object
#' @name writeSurvey
#' @rdname writeSurvey
#' @export
setMethod("writeSurvey", "GPRsurvey", function(x, fPath, overwrite=FALSE){
  if(isTRUE(overwrite)){
    cat("file may be overwritten\n")
  }else{
    fPath <- safeFPath(fPath)
  }
  x@filepath <- as.character(fPath)
  namesSlot <- slotNames(x)
  xList <- list()
#   xList[["version"]] <- "0.1"
  for(i in seq_along(namesSlot)){
    xList[[namesSlot[i]]] <- slot(x, namesSlot[i])
  }
  saveRDS(xList, fPath)
#   saveRDS(x, fPath)
})


#' @export
setMethod("writeGPR", "GPRsurvey", 
        function(x, fPath = NULL, 
                 type = c("DT1", "rds", "ASCII", "xta", "xyzv"),
                 overwrite = FALSE, ...){
    #setMethod("writeGPR", "GPRsurvey", 
    #    function(x,fPath, format=c("DT1","rds"), overwrite=FALSE){
    type <- match.arg(tolower(type), c("dt1", "rds", "ascii", "xta", "xyza"))
    mainDir <- dirname(fPath)
    if(mainDir =="." || mainDir =="/" ){
      mainDir <- ""
    }
    subDir <- basename(fPath)
    if ( !dir.exists( file.path(mainDir, subDir) )) {
      warning("Create new director ", subDir, " in ", mainDir, "\n")
      dir.create(file.path(mainDir, subDir))
    }
    for(i in seq_along(x)){
      gpr <- x[[i]]
      if(length(x@coords[[gpr@name]])>0){
        gpr@coord <- x@coords[[gpr@name]]
      }
      if(length(x@intersections[[gpr@name]])>0){
        #ann(gpr) <- x@intersections[[gpr@name]][,3:4]
        ann(gpr) <- cbind(x@intersections[[gpr@name]]$trace,
                          x@intersections[[gpr@name]]$name)
      }
      fPath <- file.path(mainDir, subDir, gpr@name)
      x@filepaths[[i]] <- paste0(fPath, ".", tolower(type))
      writeGPR(gpr, fPath = fPath, type = type , overwrite = overwrite, ...)
      message("Saved: ", fPath )
    } 
    invisible(return(x))
  }
)
#' @export
setMethod("exportFid", "GPRsurvey", function(x, fPath = NULL){
    for(i in seq_along(x)){
      gpr <- readGPR(x@filepaths[[i]])
      file_name <- file.path(fPath, paste0(gpr@name, ".txt"))
      exportFid(gpr,file_name)
      message('File "', file_name, '" created!')
      # x@coords[[gpr@name]] <- gpr@coord
    }
  }
)

#' @export
setMethod("exportCoord", "GPRsurvey",
  function(x, type = c("SpatialPoints", "SpatialLines", "ASCII"),
  fPath = NULL, driver = "ESRI Shapefile", ...){
  type <- match.arg(type, c("SpatialPoints", "SpatialLines", "ASCII"))
  if(type == "SpatialLines"){
    fPath <- ifelse(is.null(fPath), x@names[1], 
                    file.path(dirname(fPath), .fNameWExt(fPath))) 
    mySpatLines <- suppressWarnings(as.SpatialLines(x))
    dfl <- data.frame(z=seq_along(mySpatLines), 
                      row.names = sapply(slot(mySpatLines, "lines"), 
                      function(x) slot(x, "ID")))
    spldf <- sp::SpatialLinesDataFrame(mySpatLines, dfl , 
                            match.ID = TRUE)
    rgdal::writeOGR(obj = spldf, dsn = dirname(fPath), layer = basename(fPath), 
                    driver = driver, check_exists = TRUE, 
                    overwrite_layer = TRUE, delete_dsn = TRUE)
  }else if(type == "SpatialPoints"){
    fPath <- ifelse(is.null(fPath), x@names[1], 
                    file.path(dirname(fPath), .fNameWExt(fPath))) 
    spp <- as.SpatialPoints(x)
    rgdal::writeOGR(spp, dsn = dirname(fPath), layer = basename(fPath),
                    driver = driver, check_exists = TRUE,
                    overwrite_layer = TRUE, delete_dsn = TRUE)
  }else if(type == "ASCII"){
    mainDir <- dirname(fPath)
    if(mainDir =="." || mainDir =="/" ){
      mainDir <- ""
    }
    subDir <- basename(fPath)
    if ( !dir.exists( file.path(mainDir, subDir) )) {
      warning("Create new director ", subDir, " in ", mainDir, "\n")
      dir.create(file.path(mainDir, subDir))
    }
    for( i in seq_along(x)){
      gpr <- x[[i]]
      fPath <- file.path(mainDir, subDir, gpr@name)
      exportCoord(gpr, fPath = fPath, type = "ASCII", ...)
    }
  }
})

#' @export
setMethod("exportDelineations", "GPRsurvey", function(x, dirpath=""){
  for(i in seq_along(x)){
    exportDelineations(getGPR(x, id = i), dirpath = dirpath)
  }
})




#----------------- 1D-SCALING (GAIN)
#' Gain compensation
#' 
#' @name trAmplCor
#' @rdname trAmplCor
#' @export
setMethod("trAmplCor", "GPRsurvey", function(x, 
          type = c("power", "exp", "agc"),...){
  type <- match.arg(type, c("power", "exp", "agc"))
  for(i in seq_along(x)){
    y <- x[[i]]
    y@data[is.na(y@data)] <-0
    if(type=="power"){
      y@data <- .gainPower(y@data, dts = y@dz, ...)
    }else if(type=="exp"){
      y@data <- .gainExp(y@data, dts = y@dz, ...)
    }else if(type=="agc"){
      y@data <- .gainAgc(y@data, dts = y@dz, ...)
    }
    proc(y) <- getArgs()
    x@filepaths[[i]] <- .saveTempFile(y)
  #   x@proc <- c(x@proc, proc)
  }
  return(x)
  } 
)


#' Apply processing to GPRsurvey object
#' 
#' @name papply
#' @rdname papply
#' @export
setMethod("papply", "GPRsurvey", function(x, prc = NULL){
  if(typeof(prc) != "list") stop("'prc' must be a list")
  for(i in seq_along(x)){
    y <- x[[i]]
    message('Processing ', y@name, '...', appendLF = FALSE)
    for(k in seq_along(prc)){
      y <- do.call(names(prc[k]), c(x = y,  prc[[k]]))
      if(length(y@coord) > 0)   x@coords[[y@name]] <- y@coord
    }
    x@filepaths[[i]] <- .saveTempFile(y)
    message(' done!', appendLF = TRUE)
  }
  x@intersections <- list()
  x <- coordref(x)
  return(x)
  } 
)





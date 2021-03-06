#' PermuteMarginalModel -- This permutation function that will perform a wild bootstrap for a marginalmodel analysis and output the permutations to a text file.
#'
#' This function wraps all of the other functions in the MarginalModelCifti package. The output is a text file containing the permutation tests.
#' @param external_df A data frame comprising non-brain measures to model. Can be specified as a string to a csv file with appropriate headers.
#' @param concfile A character string denoting a single column text file that lists the dscalars in the same order as the external_df and wave frames.
#' @param structtype A character string denoting whether the map is volumetric ('volume'), surface-based ('surface'), a pconn ('pconn'), or a niiconn ('niiconn').
#' @param structfile A character string denoting the structural map file, used for cluster detection on surfaces only.
#' @param matlab_path A character string denoting the path to the matlab compiler. Please use v91.
#' @param surf_command A character string denoting the path to the SurfConnectivity command.
#' @param wave A data frame comprising the order of the waves (longitudinal measures) for each independent case.
#' @param notation A character string representing the model formula. Uses Wilkinson notation.
#' @param zcor A matrix defining the correlation structure set by the user, can be used to specify custom dependencies (e.g. site or kinship matrices).
#' @param corstr A character string that defines the correlation structure in a predetermined way. "Independence" is recommend for most cases.
#' @param family_dist A character string denoting the assumed underlying distribution of all input data.
#' @param dist_type A character string denoting the distribution to use for the wild bootstrap.
#' @param z_thresh A numeric that represents the threshold for Z statistics when performing cluster detection.
#' @param nboot A numeric that represents the number of wild bootstraps to perform.
#' @param p_thresh A numeric that represents the p value threshold for assessing significance.
#' @param sigtype A character string denoting cluster ('cluster'),  point ('point'), or enrichment ('enrichment') comparisons.
#' @param id_subjects A character string denoting the column for the subject ID. Only needed when FastSwE is FALSE
#' @param output_directory A character string denoting the path to the output permutation tests
#' @param fastSWE A boolean that determine the sandwhich estimator approach. If set to FALSE, will use standard R package geeglm. If set to TRUE will use custom-built estimator using rfast.
#' @param adjustment A character string denoting the small sample size adjustment to use when fastSwE is set to TRUE. Is NULL by default.
#' @param norm_external_data A boolean. If set to true, external data will be normed prior to analysis.
#' @param norm_internal_data A boolean. If set to true, MRI data will be normed per datapoint prior to analysis.
#' @param marginal_outputs A boolean. If set to true, marginal values will be output as statistical maps
#' @param marginal_matrix A numeric matrix depicting how to draw the map. Only needed if marginal_outputs is set to TRUE
#' @param enrichment_path A string depicting the path to the enrichment code. Used for enrichment analysis only (i.e. when sigtype is set to 'enrichment').
#' @param modules A csv file or array that depicts the modules for the enrichment analysis.
#' @param wb_command A character string denoting the path to the wb_command file
#' @param subsetfile A character string denoting the path to a subset selection file, to select only a subset of the participants
#' @#' @keywords wild bootstrap sandwich estimator marginal model CIFTI scalar
#' @export
#' @examples
#' max_cc <- ComputeMM_WB(cifti_map,zscore_map,resid_map,fit_map,type,external_df,
#' notation,family_dist,structtype,thresh,structfile,matlab_path,surf_command,correctiontype)
PermuteMarginalModel <- function(external_df,
                                   concfile,
                                   structtype,
                                   structfile,
                                   matlab_path,
                                   surf_command,
                                   wave = NULL,
                                   notation,
                                   zcor = NULL,
                                   corstr = NULL,
                                   family_dist = NULL,
                                   dist_type="radenbacher",
                                   z_thresh = 2.3,
                                   nboot=1000,
                                   p_thresh = 0.5,
                                   sigtype = 'cluster',
                                   id_subjects='subid',
                                   output_directory='~/',
                                   fastSwE = TRUE,
                                   adjustment = NULL,
                                   norm_external_data = TRUE,
                                   norm_internal_data = TRUE,
                                   marginal_outputs = FALSE,
                                   marginal_matrix = NULL,
                                   enrichment_path = NULL,
                                   modules = NULL,
                                   wb_command = 'wb_command',
                                   subsetfile = NULL,
                                   output_permfile = "~/permfile.txt"){
  initial_time = proc.time()
  require(purrr)
  require(cifti)
  require(gifti)
  require(geepack)
  require(Matrix)
  require(oro.nifti)
  require(mmand)
  require(parallel)
  require(Rfast)
  require(stringr)
  cifti_firstsub= NULL
  zeros_array = NULL
  curr_directory = getwd()
  setwd(output_directory)
  ciftilist <- read.csv(concfile,header=FALSE,col.names="file")
  if (is.null(subsetfile) == FALSE){
    subset_list <- read.csv(subsetfile,header=FALSE,col.names="subset")
    print("parsing imaging list")
    list_bin_expanded <- sapply(1:length(subset_list$subset),
                    function(x) {
                      SubSelection(as.character(ciftilist$file),
                                   as.character(subset_list$subset[x])
                                   )
                      }
                    )
    list_bin = as.logical(rowsums(list_bin_expanded))
    new_ciftilist = list()
    new_ciftilist$file = ciftilist$file[list_bin]
    ciftilist = as.data.frame(new_ciftilist)
  }
  print("loading imaging data")
  start_load_time = proc.time()
  if (structtype == 'volume'){
    cifti_file <- PrepVolMetric(as.character(ciftilist$file[1]))
    cifti_dim <- dim(cifti_file)
    cifti_alldata <- array(dim = c(length(ciftilist$file),cifti_dim[1]*cifti_dim[2]*cifti_dim[3]))
    count = 1
    for (filename in ciftilist$file) {
      cifti_alldata[count,] = ConvertVolume(PrepVolMetric(as.character(ciftilist$file[count])),cifti_dim)
      count = count + 1
    }      
    remove(count)
    Nelm <- dim(cifti_alldata)[2]
    cifti_nonans <- sapply(1:dim(cifti_alldata)[1],function(x){ sum(is.na(cifti_alldata[x,]))==0})
    cifti_alldata <- cifti_alldata[cifti_nonans,]    
    if (norm_internal_data == TRUE){
      for (count in 1:Nelm){
        if (var(cifti_alldata[,count]) != 0){ 
          cifti_alldata[,count] <- ((cifti_alldata[,count] - mean(cifti_alldata[,count]))/sd(cifti_alldata[,count]))
        }
      }
    }
    cifti_scalarmap <- as.data.frame(cifti_alldata)
  } 
 if (structtype == 'surface') {
    cifti_alldata <- t(data.frame((lapply(as.character(ciftilist$file),PrepSurfMetric))))
    Nelm <- dim(cifti_alldata)[2]
    cifti_dim <- Nelm
    cifti_nonans <- sapply(1:dim(cifti_alldata)[1],function(x){ sum(is.na(cifti_alldata[x,]))==0})
    cifti_alldata <- cifti_alldata[cifti_nonans,]    
    if (norm_internal_data == TRUE){
      for (count in 1:Nelm){
        if (var(cifti_alldata[,count]) != 0){ 
          cifti_alldata[,count] <- ((cifti_alldata[,count] - mean(cifti_alldata[,count]))/sd(cifti_alldata[,count]))
        }     
      }
    }
    if (fastSwE == FALSE){
      cifti_index <- 1:length(cifti_alldata)
      cifti_scalarmap <- map(cifti_index,ReframeCIFTIdata,cifti_rawmeas=cifti_alldata)
      cifti_dim=NULL
    }
 }
 if (structtype == 'pconn') {
   cifti_firstsub <- PrepCIFTI(as.character(ciftilist$file[1]))
   cifti_alldata <- array(data = NA, dim = c(length(ciftilist$file),dim(cifti_firstsub)[1]*(dim(cifti_firstsub)[1]-1)/2))
   zeros_array <- array(data=0,dim = c(dim(cifti_firstsub)[1],dim(cifti_firstsub)[2]))
   count = 1
   for (filename in ciftilist$file) { 
     cifti_temp <- PrepCIFTI(as.character(filename))
     cifti_alldata[count,] <- Matrix2Vector(cifti_temp)
     count = count + 1
   }
   Nelm <- dim(cifti_alldata)[2]
   cifti_dim <- Nelm
   cifti_nonans <- sapply(1:dim(cifti_alldata)[1],function(x){ sum(is.na(cifti_alldata[x,]))==0})
   cifti_alldata <- cifti_alldata[cifti_nonans,]
   if (norm_internal_data == TRUE){
     for (count in 1:Nelm){
       if (var(cifti_alldata[,count]) != 0) { 
         cifti_alldata[,count] <- ((cifti_alldata[,count] - mean(cifti_alldata[,count]))/sd(cifti_alldata[,count]))
       }     
     }
   }
   cifti_scalarmap <- as.data.frame(cifti_alldata)  
 }
  if (structtype == 'niiconn'){
    ciftilist <- read.csv(concfile,header=FALSE,col.names="file")
    cifti_firstsub <- PrepNiiConnMetric(as.character(ciftilist$file[1]))
    cifti_dim <- dim(cifti_firstsub)
    cifti_alldata <- array(data = NA, dim = c(length(ciftilist$file),dim(cifti_firstsub)[1]*(dim(cifti_firstsub)[1]-1)/2))
    zeros_array <- array(data=0,dim = c(dim(cifti_firstsub)[1],dim(cifti_firstsub)[2]))
    count = 1
    for (filename in ciftilist$file) { 
      cifti_temp <- PrepNiiConnMetric(filename)
      cifti_alldata[count,] <- Matrix2Vector(cifti_temp)
      count = count + 1
    }
    Nelm <- dim(cifti_alldata)[2]
    cifti_dim <- Nelm
    cifti_nonans <- sapply(1:dim(cifti_alldata)[1],function(x){ sum(is.na(cifti_alldata[x,]))==0})
    cifti_alldata <- cifti_alldata[cifti_nonans,]
    if (norm_internal_data == TRUE){
      for (count in 1:Nelm){
        if (var(cifti_alldata[,count]) != 0) { 
          cifti_alldata[,count] <- ((cifti_alldata[,count] - mean(cifti_alldata[,count]))/sd(cifti_alldata[,count]))
        }     
      }
    }
    cifti_scalarmap <- as.data.frame(cifti_alldata)
  }  
  print("loading non-imaging data")
  if (is.character(external_df)) {
    external_df <- read.csv(external_df,header=TRUE)
    if (is.null(subsetfile) == FALSE){
      external_df <- external_df[list_bin,]
    }
    external_df <- external_df[cifti_nonans,]
    df_nan <- FilterDFNA(external_df = external_df,notation = notation)
    external_df = external_df[df_nan,]
    if (structtype != "surface"){
      cifti_scalarmap = cifti_scalarmap[df_nan,]
    }
    if (structtype == "surface"){
      if (fastSwE == FALSE) {
        cifti_scalarmap = cifti_scalarmap[df_nan,]
      }
    }
    cifti_alldata = cifti_alldata[df_nan,]
    predictors <- attr(terms(notation),"term.labels")
    measnames <- c("intercept",predictors)    
    if (fastSwE == TRUE){
      external_df <- ParseDf(external_df = external_df,notation = notation,norm_data=norm_external_data)
      nmeas <- dim(external_df)[2]
    }
  }
  if (is.character(wave)) {
    print("loading longitudinal data")
    wave <- read.csv(wave,header=TRUE)
    wave <- DetermineNestedGroups(wave)
    if (is.null(subsetfile) == FALSE){
      wave = wave[list_bin]
    }
    wave = wave[cifti_nonans]
    wave = wave[df_nan]
  }
  finish_load_time = proc.time()-start_load_time
  cat("loading data complete. Time elapsed: ",finish_load_time[3],"s")  
  print("running marginal model on observed data")
  start_model_time = proc.time()
  if (fastSwE == FALSE){
    cifti_map <- lapply(cifti_scalarmap,ComputeMM,external_df=external_df,notation=notation,family_dist=family_dist,corstr=corstr,zcor=zcor,wave=wave,id_subjects=id_subjects)
    finish_model_time = proc.time() - start_model_time
    cat("modeling complete. Time elapsed: ",finish_model_time[3],"s")
    varlist <- all.vars(notation)
    nmeas <- length(varlist)
    start_normthresh_time = proc.time()
    print("Normalizing observed marginal model estimates")
    zscore_map <- map(cifti_map,ComputeZscores,nmeas)
    save(zscore_map,file = "zscore_observed.Rdata")
    resid_map <- map(cifti_map,ComputeResiduals,nmeas)
    fit_map <- map(cifti_map,ComputeFits,nmeas)
    print("thresholding observed z scores")
    thresh_map <- map(zscore_map,ThreshMap,zthresh=z_thresh)
    save(thresh_map,file = "zscore_thresh_observed.Rdata")
    finish_normthresh_time = proc.time() - start_normthresh_time
    cat("thresholding complete. Time elapsed: ", finish_normthresh_time[3],"s")
  } else
  {
    cifti_map <- lm.fit(external_df,cifti_alldata)
    beta_map <- cifti_map$coefficients
    resid_map <- cifti_map$residuals
    fit_map <- cifti_map$fitted.values
    Nelm <- dim(beta_map)[2]
    t_map <- ComputeFastSwE(X=external_df,nested=wave,Nelm=Nelm,resid_map=resid_map,npredictors=nmeas,beta_map=beta_map,adjustment=adjustment)
    finish_model_time = proc.time() - start_model_time
    cat("modeling complete. Time elapsed: ",finish_model_time[3],"s")
    start_normthresh_time = proc.time()
    print("Normalizing observed marginal model estimates")
    zscore_map <- t(sapply(1:nmeas,function(x) {(t_map[x,] - mean(t_map[x,is.finite(t_map[x,])]))/sd(t_map[x,is.finite(t_map[x,])])}))
    print("thresholding observed z scores")
    thresh_map <- t(sapply(1:nmeas,function(x) abs(zscore_map[x,]) > z_thresh))
    thresh_map[is.na(thresh_map)] <- NaN
    finish_normthresh_time = proc.time() - start_normthresh_time    
    cat("thresholding complete. Time elapsed: ", finish_normthresh_time[3],"s")
  }
  print("performing cluster detection")
  start_clust_time = proc.time()
  if (sigtype == 'cluster'){
    all_cc = matrix(data=NA,nrow=Nelm,ncol=nmeas)     
    for (curr_meas in 1:nmeas){
      thresh_array = unlist(thresh_map)
      mask_vector = 1:nmeas == curr_meas
      thresh_array <- thresh_array[mask_vector]
      thresh_array <- as.numeric(thresh_array)
      thresh_array[is.na(thresh_array)] <-  0
      if (structtype == 'volume'){
        thresh_vol <- RevertVolume(thresh_array,cifti_dim)
        observed_cc = GetVolAreas(thresh_vol)
        all_cc[,curr_meas] = ConvertVolume(observed_cc,cifti_dim)
      } else
      {
        observed_cc <- GetSurfAreas(thresh_array,structfile,matlab_path,surf_command)
        all_cc[,curr_meas] = observed_cc
      }
    }
  }
    if (sigtype == 'enrichment'){
      for (curr_meas in 1:nmeas){
        thresh_array = unlist(thresh_map)
        mask_vector = 1:nmeas == curr_meas
        thresh_array <- thresh_array[mask_vector]
        thresh_array <- as.numeric(thresh_array)
        thresh_array[is.na(thresh_array)] <-  0
        thresh_mat <- Matrix2Vector(pconn_data = zeros_array,
                                    pconn_vector = thresh_array,
                                    direction = "to_matrix")
        observed_cc <- EnrichmentAnalysis(metric_data = thresh_mat,
                                          ncols = dim(thresh_mat)[1],
                                          modules = modules, 
                                          enrichment_path = enrichment_path,
                                          matlab_path = matlab_path,
                                          output_file = paste(output_directory,'/','observed_chisqrd_',measnames[curr_meas],sep=""),
                                          tempname=paste(output_directory,'/','observed_',measnames[curr_meas],sep=""))
      if (curr_meas == 1) {
        all_cc = array(data=NA,dim=c(dim(observed_cc)[1],dim(observed_cc)[2],nmeas)) 
      }
      all_cc[,,curr_meas] <- unlist(observed_cc)
      }
    }
    finish_clust_time = proc.time() - start_clust_time
    cat("cluster detection complete. Time elapsed", finish_clust_time[3],"s")
    print("performing permutation test")
    start_perm_time = proc.time()
    seeds <- sample(.Machine$integer.max,size=nboot)
    for (iter in 1:nboot){
      WB_cc <- ComputeMM_WB(iter,resid_map=resid_map,
                           fit_map=fit_map,
                           type=dist_type,
                           external_df=external_df,
                           notation=notation,
                           family_dist=family_dist,
                           structtype=structtype,
                           thresh = z_thresh,
                           structfile=structfile,
                           matlab_path=matlab_path,
                           surf_command=surf_command,
                           corstr=corstr,
                           wave=wave,
                           zcor=zcor,
                           correctiontype = sigtype,
                           id_subjects=id_subjects,
                           cifti_dim=cifti_dim,
                           nmeas=nmeas,
                           seeds=seeds,
                           fastSwE=fastSwE,
                           adjustment=adjustment,
                           enrichment_path = enrichment_path,
                           modules = modules,
                           cifti_firstsub = zeros_array,
                           output_directory = output_directory)
      write.table(t(unlist(WB_cc)),
                  file=output_permfile,
                  sep = ",",
                  append=TRUE,
                  col.names = FALSE,
                  row.names = FALSE)
    }
      finish_perm_time = proc.time() - start_perm_time
      cat("permutation testing complete. Time elapsed",finish_perm_time[3],"s")
      
}


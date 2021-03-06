% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/RecursiveNested.R
\name{RecursiveNested}
\alias{RecursiveNested}
\title{RecursiveNested -- a recursive function that will calculate the sandwich estimator errors controlling for a blocked variable (e.g. within family/school/age)}
\usage{
RecursiveNested(iter, nests, nested, datavec, Sinit, residarray, Breadvec,
  npred, adjustment, X, Sb)
}
\arguments{
\item{iter}{The current iteration, when called it should be set to 1.}

\item{nests}{The range of blocks within the nested design should be ordered in same order as the set of whole numbers (e.g. 1,2,3,4...)}

\item{nested}{An integer vector denoting the blocks ordered by the input data}

\item{datavec}{An integer denoting the number of vertices/voxels to be tested}

\item{Sinit}{The initial covariance structure used by the sandwich estimator, default is a 1xPxdatavec numeric array set to zeros}

\item{residarray}{The residuals from the initial fit of the model to the voxel/vertex-wide dataset, should be a numeric array of num_casesXnum_voxel/vertices}

\item{Breadvec}{The "bread" of the sandwich estimator, calculated from the predictor variables P, should be a numeric array of Pxnum_cases}

\item{npred}{The number of predictors, P. Should be an integer.}

\item{S}{The covariance structure estimated from the sandwich estimator, updated upon each recursive estimation.}
}
\description{
This function is used in the fastSWEcalculation.R function to quickly calculate SwE for a nested variable.
}
\examples{
SwE <- RecursiveNested(iter=1,nests=1:Nschool,nested=Ischool,datavec=Nelm,Sinit=S0,residarray=res,Breadvec=BreadX,npred=P,adjustment=adjustment,hat_adjust=hat_adjust,S)
}
\keyword{estimator}
\keyword{fast}
\keyword{marginal}
\keyword{model}
\keyword{recursive}
\keyword{sandwich}

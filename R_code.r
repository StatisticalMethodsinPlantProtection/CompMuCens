CompMuCens <- function(dat, scale, grade=T, ckData=F){
  #Check if the required packages are installed in the working environment
  if (class(try(library(interval))) =="try-error") {
    if (class(try(library(Icens))) =="try-error") {  
      if (!require("BiocManager", quietly = TRUE))
        install.packages("BiocManager")
      #Installing the Icens package which be required by interval package 
      BiocManager::install("Icens")
    }

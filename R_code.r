CompMuCens <- function(dat, scale, grade=T, ckData=F){
  #Check if the required packages are installed in the working environment
  if (class(try(library(interval))) =="try-error") {
    if (class(try(library(Icens))) =="try-error") {  
      if (!require("BiocManager", quietly = TRUE))
        install.packages("BiocManager")
      #Installing the Icens package, which is required by the Interval package
      BiocManager::install("Icens")
    }
    #Installing the interval package
    install.packages ("interval", repos="http://cloud.r-project.org")
  }
  if (class(try(library(dplyr))) =="try-error") {
    #Installing the dplyr package.
    install.packages("dplyr", repos="http://cloud.r-project.org")
  }

  library(dplyr)     #attach package 'dplyr'
  library(interval)  #attach package 'interval'
  
  # Converting data into a censored data format
  if (grade==T) {
    ######class value
    if (scale[1]==0) {
      if (scale[length(scale)-1]==100) {
        Scale=unique(scale)
        dat$Slow=ifelse(dat$x==1, 0,
                        ifelse(dat$x==length(scale), 100,
                               suppressWarnings(   #Suppress Warnings 
                                 as.numeric(lapply(dat$x, function(x)Scale[x-1])) ) ))
        dat$Sup=ifelse(dat$x==1, 0,
                       ifelse(dat$x==length(scale), 100,
                              suppressWarnings(   #Suppress Warnings 
                                as.numeric(lapply(dat$x, function(x)Scale[x])) ) ))
      } else {
        Scale=scale
        dat$Slow=ifelse(dat$x==1, 0,
                        suppressWarnings(   #Suppress Warnings 
                          as.numeric(lapply(dat$x, function(x)Scale[x-1])) ) )
        dat$Sup=ifelse(dat$x==1, 0,
                       suppressWarnings(   #Suppress Warnings 
                         as.numeric(lapply(dat$x, function(x)Scale[x])) ) )
      }
    } else {
      if (scale[length(scale)-1]==100) {
        Scale=c(0,unique(scale))
        dat$Slow=ifelse(dat$x==length(scale), 100,
                        suppressWarnings(   #Suppress Warnings 
                          as.numeric(lapply(dat$x, function(x)Scale[x])) ) )
        dat$Sup=ifelse(dat$x==length(scale), 100,
                       suppressWarnings(   #Suppress Warnings 
                         as.numeric(lapply(dat$x, function(x)Scale[x+1])) ) )
      } else {
        if (scale[length(scale)]==100){
          Scale=c(0,scale)
        } else {
          Scale=c(0,scale,100)
        }
        dat$Slow=as.numeric(lapply(dat$x, function(x)Scale[x]))
        dat$Sup=as.numeric(lapply(dat$x, function(x)Scale[x+1]))
      }  
    }
    outPrintD <- dat %>% rename(ClassValue=x)
    dat <- dat %>% select (treatment, Slow, Sup) 
  } else {
    ######NPE
    if (scale[1]==0) {
      if (scale[length(scale)-1]==100) {
        Scale=unique(scale)
        dat$Slow=ifelse(!dat$x %in% c(0,100), 
                        suppressWarnings(   #Suppress Warnings 
                          as.numeric(lapply (dat$x, function(x) Scale[max(which(x>Scale))]))),
                        dat$x)
        dat$Sup=as.numeric(lapply(dat$x, function(x) Scale[min(which(x<=Scale))]) )
      } else {
        Scale=scale
        dat$Slow=ifelse(!dat$x==0, 
                        suppressWarnings(   #Suppress Warnings 
                          as.numeric(lapply (dat$x, function(x) Scale[max(which(x>Scale))]))),
                        dat$x)
        dat$Sup=as.numeric(lapply(dat$x, function(x) Scale[min(which(x<=Scale))]) )
      }
    } else {
      if (scale[length(scale)-1]==100) {
        Scale=c(0,unique(scale))
        dat$Slow=ifelse(!dat$x %in% c(0,100), 
                        suppressWarnings(   #Suppress Warnings 
                          as.numeric(lapply (dat$x, function(x) Scale[max(which(x>Scale))]))),
                        dat$x)
        dat$Sup=ifelse(!dat$x==0,
                       as.numeric(lapply(dat$x, function(x) Scale[min(which(x<=Scale))])),
                       Scale[2])
      } else {
        if (scale[length(scale)]==100){
          Scale=c(0,scale)
        } else {
          Scale=c(0,scale,100)
        }
        dat$Slow=ifelse(!dat$x==0, 
                        suppressWarnings(   #Suppress Warnings 
                          as.numeric(lapply (dat$x, function(x) Scale[max(which(x>Scale))]))),
                        dat$x)
        dat$Sup=ifelse(!dat$x==0,
                       as.numeric(lapply(dat$x, function(x) Scale[min(which(x<=Scale))])),
                       Scale[2])
      }  
    }
    outPrintD <- dat %>% rename(MidPoint=x)
    dat <- dat %>% select (treatment, Slow, Sup) 
  }
  
  #Convert to Interval Data (To confirmation the scale input format)
  outPrintD$intervals=as.character(Surv(outPrintD$Slow, outPrintD$Sup, type = "interval2"))
  outPrintD <- outPrintD %>% select(-Slow,-Sup) 
  
  # Extracting score statistics from each treatment group
  mAll=ictest(Surv(Slow, Sup, type = "interval2") ~ treatment, scores="wmw",data=dat) 
  #Create a tag data frame for score statistics
  anaD=dat %>% mutate(score=mAll$scores) %>%
    group_by(treatment) %>% summarise(score=sum(score)) %>%
    arrange(desc(score)) %>%
    mutate (mk=row_number ()) %>% # "mk" being the descending order of the score statistic for each treatment.
    as.data.frame()
  
  # Creating a data frame to store the results of the analysis
  out=anaD %>% arrange(desc(mk)) %>% mutate (V1=treatment,
                                             V2=lead(treatment),
                                             V1n=mk,
                                             V2n=lead(mk),
                                             pvalue=NA,
                                             pvalue2=NA,
                                             conclusion="",
                                             conc1="") %>%  as.data.frame()
  
  # Creating a copy of the original data
  dat1=dat %>% rowwise() %>% #Run code row by row 
    mutate (treat=which (anaD$treatment %in% treatment)) # "treat" being the descending order of the score statistic for each treatment
  
  # Pairwise comparison is performed in a loop.
  # The significance level is adjusted based on the Bonferroni adjustment. For example, if there are three treatments A, B, and C, and the order in which they are administered is fixed, then we only need to compare A to B and B to C. We don't need to compare A to C, so the total number of comparisons is 2. Therefore, the significance level should be alpha/2.
  for (i in c(1:(nrow(out)-1))) {
    # Because ictest() performs the comparison according to the order of treatments, it needs to sort the treatments first.
    testD=dat1 %>% filter(treatment %in% c(out[i,4],out[i,5])) %>% 
      select(-treatment) %>% arrange(treat)   
    m22=ictest(Surv(Slow, Sup, type = "interval2") ~ treat, scores="wmw",
               data=testD, alternative="greater")  
    out[i,8]=m22$p.value
    if (out[i,8]>(0.05/(nrow(out)-1))) {
      m221=ictest(Surv(Slow, Sup, type = "interval2") ~ treat, scores="wmw",
                  data=testD, alternative="two.sided")  
      out[i,9]=m221$p.value
      out[i,10]=ifelse(m221$p.value>(0.05/(nrow(out)-1)), paste0(out[i,4],"=",out[i,5]), paste0(out[i,4],"<",out[i,5]))
      rm(m221)
    } else {  out[i,10]=paste0(out[i,4],">",out[i,5])   }
    
    if (i==1){  out[i,11]=out[i,10]  } else {
      out[i,11]=substr(out[i,10],start=which( unlist(strsplit(out[i,10],split="")) %in% c(">", "<", "=") ),stop=nchar(out[i,10]))
    }
    rm(testD, m22)
  }
  
  #Renaming the columns in the analysis results 
  colnames(out)[c(4,5,8,9)]=c("treat1","treat2", "p-value for H0: treat1 ≤ treat2",
                              "p-value for H0: treat1 = treat2" )
  
  #Creating the final output file
  if (ckData==F){
    out1=list( U.Score=out[,c(1,2)],
               Hypothesis.test=out[-nrow(out), c(4,5,8,9)],
               adj.Signif=0.05/(nrow(out)-1),
               Conclusion=paste(out[-nrow(out),11], collapse = ""))
  } else {
    out1=list( inputData=outPrintD,
               U.Score=out[,c(1,2)],
               Hypothesis.test=out[-nrow(out), c(4,5,8,9)],
               adj.Signif=0.05/(nrow(out)-1),
               Conclusion=paste(out[-nrow(out),11], collapse = ""))
  }

  return(out1)
}

# Example1
#Entering your data(ordinal rating scores)
trAs=c(5,4,2,5,5,4,4,2,5,2,2,3,4,3,2,2,6,2,2,4,2,4,2,4,5,3,4,2,2,3)
trBs=c(5,3,2,4,4,5,4,5,4,4,6,4,5,5,5,2,6,2,3,5,2,6,4,3,2,5,3,5,4,5)
trCs=c(2,3,1,4,1,1,4,1,1,3,2,1,4,1,1,2,5,2,1,3,1,4,2,2,2,4,2,3,2,2)
trDs=c(5,5,4,5,5,6,6,4,6,4,3,5,5,6,4,6,5,6,5,4,5,5,5,3,5,6,5,5,5,6)
#Data shaping into input format
inputData=data.frame(treatment=c(rep("A",30),rep("B",30),rep("C",30),
                                 rep("D",30)),
                     x=c(trAs, trBs, trCs, trDs))
#Perform analysis using CompMuCens() function
CompMuCens(dat=inputData, scale=c(0,3,6,12,25,50,75,88,94,97,100,100),ckData=T)

# example2
#Entering the data(ordinal rating scores)
trAm=c(18.5,9,1.5,18.5,18.5,9,9,1.5,18.5,1.5,1.5,4.5,9,4.5,1.5,1.5,37.5,1.5,
       1.5,9,1.5,9,1.5,9,18.5,4.5,9,1.5,1.5,4.5)
trBm=c(18.5,4.5,1.5,9,9,18.5,9,18.5,9,9,37.5,9,18.5,18.5,18.5,1.5,37.5,1.5,
       4.5,18.5,1.5,37.5,9,4.5,1.5,18.5,4.5,18.5,9,18.5)
trCm=c(1.5,4.5,0,9,0,0,9,0,0,4.5,1.5,0,9,0,0,1.5,18.5,1.5,0,4.5,0,9,1.5,1.5,
       1.5,9,1.5,4.5,1.5,1.5)
trDm=c(18.5,18.5,9,18.5,18.5,37.5,37.5,9,37.5,9,4.5,18.5,18.5,37.5,9,37.5,
       18.5,37.5,18.5,9,18.5,18.5,18.5,4.5,18.5,37.5,18.5,18.5,18.5,37.5)
#Data shaping into input format
inputData=data.frame(treatment=c(rep("A",30),rep("B",30),rep("C",30),
                                 rep("D",30)),
                     x=c(trAm, trBm, trCm, trDm))
#Perform analysis using CompMuCens() function
CompMuCens(dat=inputData, scale=c(0,3,6,12,25,50,75,88,94,97,100,100), grade=F)

pairwise.t.test(inputData$x, inputData$treatment, "bonf")

# example 3
#Data shaping into input format
inputData=data.frame(treatment=c(rep("A",30),rep("B",30),rep("C",30),
                                 rep("D",30), rep("E",30),rep("F",30)),
                     x=c(trAs, trBs, trCs, trDs, trAs, trDs))
#Perform analysis using CompMuCens() function
CompMuCens(dat=inputData, scale=c(0,3,6,12,25,50,75,88,94,97,100,100))


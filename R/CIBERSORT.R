CIBERSORT <- function(response,features, transform, usegenes, norm=T, nu= c(0.25,0.5,0.75), optim.nu =F, mc.cores=3, ...) {

  if (norm) features <- apply(features, 2, function(x) x / mean(x) * mean(response))

  response <- transform(response) -> allresponse
  response <- response[usegenes]
  allresponse <- allresponse[intersect(rownames(features),names(allresponse))]

  features <- transform(features[usegenes, ])
#
#   features <- apply(features,2,scale)
#   response <- scale(response)

    #proper way to choose nu
    #set up CV scheme
    if (optim.nu & length(nu)>1) {
      cvorder <- sample(1:nrow(features), nrow(features))
      cvset <- rep(c(1:5), length.out = nrow(features))
      nuerror <- sapply(nu, function(n) {
      tuning <- do.call(rbind,parallel::mclapply(1:5, function(i) {
        train <- cvorder[cvset != i]
        test <- cvorder[cvset == i]
        svr <- e1071::svm(features[train,], y = response[train], type="nu-regression", kernel="linear", nu = n,  ...)
        out <- data.frame(real = response[test], predicted = e1071:::predict.svm(svr, newdata = features[test,]))
      }, mc.cores=mc.cores))
      sqrt(mean((tuning$predicted - tuning$real) ^2))
      })
      nu <- nu[which.min(nuerror)]
    }

      SVR <- parallel::mclapply(nu, function(n) e1071::svm(features, y = response, type="nu-regression", kernel="linear", nu = n,  ...))

      get_RMSE <- function(SVR, truey) {
        predicted <-   e1071:::predict.svm(SVR)
        sqrt(mean((predicted - truey) ^2))
      }
      RMSE <- sapply(SVR, get_RMSE, truey = response)
      SVR <- SVR[[which.min(RMSE)]]

      coef <- t(SVR$coefs) %*% SVR$SV
      coef[coef<0] <- 0


      #P value estimation.
      predicted <- e1071:::predict.svm(SVR)
      test_statistics <- cor(predicted , response)



      #CIBERSORT is then run on m*i to produce a vector of estimated cellular fractions, f*i. CIBERSORT determines the correlation coefficient R*i between the random mixture m*i and the reconstituted mixture, f*i ?? B. This process is repeated for I iterations (I = 500 in this work) to produce R*.

      out <- t(coef/sum(coef))
      attr(out, "p") <-  cor.test(predicted , response)$p.value
      attr(out, "SV") <- SVR$SV

      out
}



#'Runs CIBERSORT for decomposing bulk RNA-seq samples using a single cell reference
#'
#' This is a custom implementation of the algorithm described by Newman et al (Nautre Methods 12:453-457). CIBERSORT is an algorithm for estimating the cell type composition of a bulk sample, given a gene expression profile of the sample and a known gene expression profile for each cell type potentially contributing to the sample.
#'@param exprs A data frame or matrix of raw read counts of \epmh{bulk} RNA-seq samples. Column names correspond to sample names, row names to genes.
#'@param base A matrix of read counts representing the gene expression profiles of all cell types that might contribute to the bulk samples. See examples below for how to generate this object from an object of class  \code{seurat}.
#'@param design A named vector assigning sample names to sample class, see examples below.
#'@param markergenes A vector of genes to be included in the analysis, defaults to \code{intersect( rownames(mean_by_cluster),  rownames(exprs) )}
#'@param transform A function to be applied to columns of \code{exprs} and \{base} following normalization. Defaults to no transformation since bulk RNA-seq profiles are generated by pooling up RNA from constituent cell types. In the original CIBERSORT paper, a logarithmic transform was used.
#'@param nu Different values of nu to evaluate support vector regression at, see \code{\link{[e1071]svm}}. Nu defines how many support vectors (i.e. genes) to use in regression.
#'@param optim.nu In the original CIBERSORT implementation, SVR is evaluated at several values of nu and the value with the best RSME is chosen. This can lead to overfitting. If \code{optim.nu} is set to \code{TRUE}, the value for nu is chosen by cross validation, which leads to longer runtimes.
#'@param mc.cores Number of cores used, e.g. for the parallel evaluation at different balues of nu.
#'@param ... Parameters passed to \code{\link[e1071]svm}
#'@return A data frame in long format suitable for plotting with ggplot2.
#'@examples
#'\dontrun{
#'#See also package vignette CIBERORT.Rmd
#'#1. identify marker genes from a seurat object
#'NicheMarkers10x <- FindAllMarkers(NicheData10x, test.use = "roc")
#'usegenes <- unique(NicheMarkers10x$gene[(NicheMarkers10x$myAUC > 0.8 |NicheMarkers10x$myAUC < 0.2) ])
#'
#'#2. compute mean expression per cell type
#'mean_by_cluster <- do.call(cbind, lapply(unique(NicheData10x@ident), function(x) {
#'apply(NicheData10x@raw.data[usegenes,NicheData10x@cell.names][,NicheData10x@ident == x], 1,mean )
#'}))
#'colnames(mean_by_cluster) <- unique(NicheData10x@ident)
#'
#'#3. Create a vector that maps samples to biological class
#'LCM_design <- NicheMetaDataLCM$biological.class
#'names(LCM_design) <- NicheMetaDataLCM$id
#'
#'4. Run CIBERSORT
#'CIBER <- runCIBERSORT(NicheDataLCM, mean_by_cluster,usegenes, LCM_design, mc.cores=3)
#'}
#'@export
runCIBERSORT <- function(exprs, base,design, markergenes = intersect( rownames(mean_by_cluster),  rownames(exprs) ),transform=function(x) x,nu = c(0.25,0.5,0.75), optim.nu = F, mc.cores= 3, ...) {

  res <- list()
  for (i in 1:ncol(exprs)) {
    x <- exprs[,i]
    names(x) <- rownames(exprs)
    res[[i]] <- CIBERSORT(x, features=base, transform=transform, usegenes = intersect(markergenes, rownames(exprs)), nu=nu, optim.nu = optim.nu, mc.cores = mc.cores, ...)
  }
  #out <- apply(exprs,2, CIBERSORT, features=mean_by_cluster, kernel=kernel, cost =cost, method = method,alpha=alpha, gamma=gamma, transform=transform, usegenes = intersect(markergenes, rownames(exprs)), norm=norm, nu=nu)
  pvals <- data.frame(
    pvals = sapply(res, attr, "p"),
    samples = colnames(exprs)
  )

  svs <- lapply(res, attr, "SV")


  out <- do.call(cbind,res)
  colnames(out) <- colnames(exprs)
  rownames(out) <- colnames(mean_by_cluster)
  out <- reshape2::melt(out)
  out$experiment <- design[out$Var2]
  colnames(out) <- c("CellType","SampleID","Fraction","SampleClass")
  out
}

plotCIBER <- function(ciber,nrow=NULL) {
  ggplot(aes(x = Var1, y = value, fill=Var1), data=ciber) + geom_bar(stat="summary", fun.y=mean) + scale_x_discrete(labels = annos) + scale_fill_manual(values=colors, labels=annos, guide=F) + facet_wrap(~experiment,nrow=nrow) + geom_errorbar(stat="summary",fun.ymin = function(x) mean(x)-sd(x), fun.ymax = function(x) mean(x)+sd(x), width=0.2) + theme(axis.text.x =  element_text(angle=90, size=8)) + ylab("% of population") + xlab("")
}


get_sample <- function(runid, usegenes,npop=10,ncell=1000, replicates = 1, kernel ="radial",cost = 1, transform="log2", method="SVR",alpha=0.5, gamma=NULL, nu = c(0.25,0.5,0.75)){
  raw <- seurat@raw.data[,seurat@cell.names]

  #if (transform == "log2") transform <- log2p1 else transform <- lin

  what.to.sample <- sample(as.character(unique(seurat@ident)), npop)
  fractions <- rdirichlet(1, rep(1,npop))
  fractions <- round(ncell*rdirichlet(1, rep(1,npop)))

  out <- replicate(replicates, {
  gex <- lapply(1:length(what.to.sample), function(x) {
    use <- sample(seurat@cell.names[seurat@ident == what.to.sample[x]], fractions[x], replace=T)
    if (length(use)==1) raw[,use] else apply(raw[,use],1,sum)
  })
  gex <- do.call(cbind,gex)
  gex <- apply(gex,1,sum)


  # all <- rep(0, length(unique(seurat@ident)) )
  # names(all ) <- unique(seurat@ident)
  # all[what.to.sample] <- fractions
  #
  # gex <- mean_by_cluster %*% all
  # gex <- gex[,1]


  usegenes <- intersect(usegenes, names(gex))#,size = ngene)



  #features <- transform(mean_by_cluster[usegenes, ])
  test_ciber <- CIBERSORT(gex, mean_by_cluster, kernel, cost, transform, usegenes,method = method,alpha=alpha, gamma=gamma, nu=nu)
  })

  all <- rep(0, length(unique(seurat@ident)) )
  names(all ) <- unique(seurat@ident)
  all[what.to.sample] <- fractions/ncell


  test_ciber <- apply(out,1,mean)
  if (method == "SVR") merged <- data.frame(truth = all, result = test_ciber, cluster = names(all),runid = runid) else merged <- data.frame(truth = all, result = test_ciber, cluster = names(all),runid = runid)
  merged

}

runSampling <- function(usegenes, nsamples=15,npop=10,replicates=1,ncell=1000, kernel ="radial",cost = 1, transform="log2", method = "SVR",alpha=0.5, gamma = NULL, nu=c(0.25,0.5,0.75)) {
  samples <- lapply(1:nsamples, get_sample, usegenes=usegenes, npop=npop,ncell=ncell, replicates=replicates,kernel =kernel,cost = cost, transform=transform, method=method, alpha=alpha, gamma=gamma, nu=nu)
  rsqrs <- sapply(samples, function(x) cor(x$truth,x$result)^2)
  rho <- sapply(samples, function(x) cor(x$truth,x$result,method="spearman"))
  out <- do.call(rbind, samples)
  out$gamma <- gamma; out$npop <- npop
  list(rsqr = mean(rsqrs), rho = mean(rho), samples = out, allrho = rho, allrsqrs = rsqrs)
}




get_sample_fixed <- function(runid, populations,frequencies,usegenes,ncell=1000, kernel ="radial",cost = 1, transform="log2", method="SVR",alpha=0.5, gamma=NULL){
  raw <- as.matrix(raw)
  # if (transform == "log2") transform <- log2p1 else transform <- lin

  what.to.sample <- populations
  fractions <- round(ncell*frequencies)
  gex <- lapply(1:length(what.to.sample), function(x) {
    use <- sample(cell.names[ident == what.to.sample[x]], fractions[x], replace=T)
    if (length(use)==1) raw[,use] else apply(raw[,use],1,sum)
  })
  gex <- do.call(cbind,gex)
  gex <- apply(gex,1,sum)
  all <- rep(0, length(unique(ident)) )
  names(all ) <- unique(ident)
  all[what.to.sample] <- fractions/ncell

  # all <- rep(0, length(unique(seurat@ident)) )
  # names(all ) <- unique(seurat@ident)
  # all[what.to.sample] <- fractions
  #
  # gex <- mean_by_cluster %*% all
  # gex <- gex[,1]


  usegenes <- intersect(usegenes, names(gex))#,size = ngene)
  # mean_by_cluster <- apply(mean_by_cluster, 2, function(x) x / mean(x) * mean(gex))



  # features <- transform(mean_by_cluster[usegenes, ])
  # test_ciber <- CIBERSORT(transform(gex[usegenes]), features, kernel, cost, method = method,alpha=alpha)
  test_ciber <- CIBERSORT(gex, mean_by_cluster, kernel, cost, transform = transform, usegenes = usegenes, method = method,alpha=alpha, gamma = gamma)
  if (method == "SVR") merged <- data.frame(truth = all, result = test_ciber[,1], cluster = names(all),runid = runid, stringsAsFactors = F) else merged <- data.frame(truth = all, result = test_ciber, cluster = names(all),runid = runid, stringsAsFactors = F)
  merged

}


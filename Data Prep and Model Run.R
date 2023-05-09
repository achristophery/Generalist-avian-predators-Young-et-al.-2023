rep.col<-function(x,n){
  matrix(rep(x,each=n), ncol=n, byrow=TRUE)
}
scale_df <- function(dfr) {
  x <- dfr
  cols <- sapply(dfr, is.numeric)
  scaledvars <- scale(dfr[, cols])
  x[, cols] <- scaledvars
  return(x) 
}
library(dplyr)
library(jagsUI)
library(loo)
library(tidyr)


y17<- as.matrix(read.csv(file = "y17Rav.csv", header = F))
y18<- as.matrix(read.csv(file = "y18Rav.csv", header = F))
y19<- as.matrix(read.csv(file = "y19Rav.csv", header = F))
y20<- as.matrix(read.csv(file = "y20Rav.csv", head = F))
y<- array(c(y17, y18, y19, y20), c(38,3,4))
rav100.juoc<- read.csv(file = "100m_juoc.csv", header = T)
rrj<- rav100.juoc %>% 
  arrange(Id) %>% 
  dplyr::select(-Id) %>% 
  as.matrix()
rrj<- scale(rrj)

rrcov<- read.csv(file = "RR Covariates.csv", header = T)

rrcov<- rrcov %>%
  group_by(Id) %>% 
  mutate(water = min(dist_pond, dist_stream, na.rm=TRUE)) %>% 
  ungroup()
rrwater<- as.matrix(scale(rrcov$water), ncol = 1)
rrroad<- as.matrix(scale(rrcov$road), ncol = 1)
rrcliff<- as.matrix(scale(rrcov[,2]), ncol = 1)
rrpond<- as.matrix(scale(rrcov$dist_pond), ncol = 1)
rrstream<- as.matrix(scale(rrcov$dist_stream), ncol = 1)
rrtriangle<- as.matrix(scale(rrcov$triangle), ncol = 1)
rrtri<- as.matrix(scale(rrcov$tri1k_mean), ncol = 1)

sb<- read.csv(file = "mean songbird abundance.csv", header = T)
sb17<- sb %>% filter(Year == 2017)
sb18<- sb %>% filter(Year == 2018)
sb19<- sb %>% filter(Year == 2019)
sb20<- sb %>% filter(Year == 2020)
sbd<- data.frame("1" = sb17$mean, "2" = sb18$mean, "3" = sb19$mean, "4" = sb20$mean)
mean(sbd$X1, na.rm = TRUE) #5.5
sbd<- sbd %>% replace_na(list(X1 = 5.5))
sb<- scale(sbd)
sb<- as.data.frame(sb)
gs<- read.csv(file = "ground squirrels.csv", header = T)
gs<- gs %>% 
  select(occ) %>% 
  mutate(occ = occ + 1)
gb<- read.csv(file = "prpa rr sage mean.csv", header = T)
gb<- gb %>% dplyr::select(-X, -sage.real)
pm<- read.csv(file = "pema.rr.den.csv", header = T)
pm<- pm %>% dplyr::select(-X)
sm<- cbind(gb, pm)
sm<- sm %>% 
  mutate(d17 = gbpm17 + pema17) %>% 
  mutate(d18 = gbpm18 + pema18) %>% 
  mutate(d19 = gbpm19 + pema19) %>% 
  mutate(d20 = gbpm20 + pema20) %>% 
  dplyr::select(d17:d20)
sm<- scale_df(sm)
sbj<- sb*rrj
smj<- sm*rrj

rrtri<- as.matrix(scale(rrcov$tri1k_mean), ncol = 1)
tri<- matrix(c(rrtri, rrtri,rrtri,rrtri), ncol = 4, nrow = 38)
tri<- array(c(rrtri, rrtri,rrtri,rrtri), dim = c(38,3,4))

cat(file = "Final Cora Model Text.txt", 
    "model {
    # Specify priors
    alpha ~ dnorm(0, 0.01)
    beta0 ~ dnorm(0,0.01)
    beta.juoc ~ dnorm(0, 0.01)
    beta.water ~ dnorm(0, 0.01)
    beta.tri ~ dnorm(0, 0.01)

    for (k in 1:(nyear-1)){
    a.col[k] ~ dnorm(0, 0.01)
    b.ext[k] ~ dnorm(0, 0.01)
    alpha.det[k] ~ dnorm(0,0.01)
    }
    alpha.det[nyear] ~ dnorm(0,0.01)
    
    #beta.treatment[1]<- 0
    #for(i in 2:3){
    #beta.treatment[i] ~ dnorm(0,0.01)
    #}
    # Ecological submodel: Define state conditional on parameters
    for (i in 1:nsite){
    logit(psi1[i,1])<- alpha + beta.juoc*rr100[i,1] + beta.water*water[i,1]
    z[i,1] ~ dbern(psi1[i,1]) 
    for (k in 2:nyear){
    logit(muZ[i,k])<- a.col[k-1] + b.ext[k-1]*z[i,k-1] + beta.juoc*rr100[i,k] + beta.water*water[i,1]
    z[i,k]~ dbern(muZ[i,k])
    
    } #k
    } #i
    # Observation model
    for (i in 1:nsite){
    for (j in 1:nrep){
    for (k in 1:nyear){
    y[i,j,k] ~ dbern(muy[i,j,k])
    muy[i,j,k]<- z[i,k]*p[i,j,k]
    logit(p[i,j,k])<-alpha.det[k] + beta.tri*tri[i,j,k]
    y.new[i,j,k] ~  dbern(muy[i,j,k]) # sample new observation # posterier predictive distribution
    log.lik[i,j,k]  <- logdensity.bin(y[i,j,k],muy[i,j,k],1) 
    log.lik.new[i,j,k]  <- logdensity.bin(y.new[i,j,k],muy[i,j,k],1) # for p-value
    
    } #k
    } #j
    log.lik.cum[i] <- sum(log.lik[i,,])
    } #i
      mean.p[1]<- exp(alpha.det[1]) / (1 + exp(alpha.det[1]))
  for(j in 2:nyear){
    mean.p[j]<- exp(alpha.det[j]) / (1 + exp(alpha.det[j]))
  }
    n.occ[1]<-sum(z[1:nsite,1])
    for (k in 2:nyear){
    n.occ[k] <- sum(z[1:nsite,k])
    }
        for (i in 1:nsite){
      for(k in 1:4){
    cell.obs[i,k] <- sum(y[i,,k])
    cell.new[i,k] <- sum(y.new[i,,k])
    cell.exp[i,k] <- sum(p[i,,k])
    cell.d.obs[i,k] <- (cell.obs[i,k]^0.5 - cell.exp[i,k]^0.5)^2
    cell.d.new[i,k] <- (cell.new[i,k]^0.5 - cell.exp[i,k]^0.5)^2
      }
        }
    alpha.vec[1]<-ilogit(alpha) #mean psi at avg covariate conditions
    psi.vec[1]<-ilogit(beta0) #mean psi at avg covariate conditions
    D.obs <- sum(cell.d.obs[,])
    D.new <- sum(cell.d.new[,])
    p.val <- (D.obs < D.new)
    for(j in 2:nyear-1){
      phi[j]<-ilogit(a.col[j]+b.ext[j])
      gamma[j]<-ilogit(a.col[j])
 
 }

    for(j in 2:nyear){
      psi.vec[j]<-psi.vec[j-1]*phi[j-1] + (1-psi.vec[j-1])*gamma[j-1]  
      turnover[j-1]<- ((1 - psi.vec[j-1]) * gamma[j-1])/( (1 - psi.vec[j-1]) * gamma[j-1] + phi[j-1]*psi.vec[j-1])
      }
    } #end of model
    "
)

cora.data<- list(y = y, nsite = 38, nrep = 3, nyear = 4, rr100 = rrj, tri = tri, water = rrwater)
params<- c("n.occ", "log.lik.cum", "alpha.vec", "psi.vec","mean.p","beta.tri", "beta.juoc", "beta.water", "p.val", "D.obs", "D.new", "alpha.det")
ni <- 1000
nt <- 5
nb <- 10
nc <- 3
na <- 100

inits<-function(){list(z= matrix(1, nrow = 38, ncol = 4))}

cora.out<- jags(cora.data, inits, params, "Final CORA Model Text.txt", n.adapt = na, n.chains = nc, n.thin = nt, n.iter = ni, n.burnin = nb, parallel = F)
cora.out

lr.cora <- loo(cora.out$sims.list$log.lik.cum)


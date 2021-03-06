# Usage: 
# Rscript CompareMayoGTExTCGA.nonparametric.R \
#         --gtex ../GTEx_Predictions/chr21/predicted_expression.txt \
#         --mayo ../Mayo_Predictions/chr21/predicted_expression.txt \
#         --tcga ../TCGA_ObservedNormalExpression/TCGA_Normal_Expression_Matrix.HGNC.txt \
#         --chromosome 21
#         --output_pre ./test_outputs.chr21

##########################
# INSTALL R DEPENDENCIES #
##########################

options(warn=-1)

cat("
###########################
Step 1: Installing Packages
###########################
\n")

packages    <- c("optparse")
uninstalled <- setdiff(packages, rownames(installed.packages()))
installed   <- setdiff(packages, uninstalled)
lapply(installed,require,character.only=TRUE)  

if ( length(uninstalled) != 0 ) {
  install.packages( uninstalled, repos="http://cran.r-project.org")
  lapply( uninstalled, require, character.only=TRUE )
}

########################
# PARSE USER ARGUMENTS #
########################

cat("
#########################
Step 2: Parsing Arguments
#########################
\n")

ParseArgs <- function()
{
  option.list <- list(
    make_option(c("--gtex"), action="store_true",
                default=NA, type="character",
                help="Path to file containing imputed TCGA expression
                using the GTEx prostate (PredictDB) reference panel."),
    make_option(c("--mayo"), action="store_true",
                default=NA, type="character",
                help="Path to file containing imputed TCGA expression
                using the Mayo Clinic (dbGaP) reference panel."),
    make_option(c("--tcga"), action="store_true",
                default=NA, type="character",
                help="Path to file containing observed TCGA expression."),
    make_option(c("--chromosome"), action="store_true",
                default=NA, type="character",
                help="Chromosome number to be analyzed."),
    make_option(c("--output_prefix"), action="store_true",
                default=NA, type="character",
                help="Path / prefix for output files comparing observed
                and imputed (via GTEx, Mayo) TCGA prostatic expression.")
  )
  parser   <- OptionParser(usage = "Rscript %prog [flag] value ...",
                         add_help_option=TRUE, option_list=option.list)
  cmd.args <- parse_args(parser, positional_arguments = FALSE)
  params   <- as.character(cmd.args)
}

params <- ParseArgs()

# Required input files
gtex_input <- params[1]
mayo_input <- params[2]
tcga_input <- params[3]
chromosome <- params[4]
output_pre <- params[5]

if ( is.na(gtex_input) || is.na(mayo_input) || is.na(tcga_input) || is.na(chromosome) || is.na(output_pre) )
{
  stop("Missing user inputs. Required inputs are '--gtex', '--mayo', '--tcga', '--chromosome',
        \tand '--output_pre'. Refer to usage (-h flag) for additional inputs and arguments.")
}

#############################
# COMPARE EXPRESSION VALUES #
#############################

cat("
###################################
Step 3: Comparing Expression Values
###################################
\n")

# Read in TCGA Normal Expression; Set column and row names
# Input: "TCGA_Normal_Expression_Matrix.HGNC.txt"
tcga_normal = read.table(tcga_input, stringsAsFactors=F)
tcga_normal = t(tcga_normal)
colnames(tcga_normal) = tcga_normal[1, ]
tcga_normal = tcga_normal[-1, ]
rownames(tcga_normal) = tcga_normal[,1]
tcga_normal = tcga_normal[,-1]

tcga_normal = as.data.frame(tcga_normal, stringsAsFactors=F)

# Read in GTEx Normal Expression; Set column and row names
gtex_tcga = read.table(gtex_input,stringsAsFactors=F)
colnames(gtex_tcga) = gtex_tcga[1, ]
gtex_tcga = gtex_tcga[-1, ]
rownames(gtex_tcga) = gtex_tcga[,1]
gtex_tcga = gtex_tcga[,-1]

# Reorder for consistency
gtex_tcga = gtex_tcga[match(rownames(tcga_normal), gtex_tcga$IID),]

# Read in Mayo Normal Expression; Set column and row names
mayo_tcga = read.table(mayo_input,stringsAsFactors=F)
colnames(mayo_tcga) = mayo_tcga[1, ]
mayo_tcga = mayo_tcga[-1, ]
rownames(mayo_tcga) = mayo_tcga[,1]
mayo_tcga = mayo_tcga[,-1]

# Reorder for consistency
mayo_tcga = mayo_tcga[match(rownames(tcga_normal), mayo_tcga$IID),]

genes_in_common = intersect(intersect(colnames(mayo_tcga),colnames(gtex_tcga)), colnames(tcga_normal))

for( gene_name in genes_in_common ){

  expression_concat = data.frame(scale(as.numeric(tcga_normal[[gene_name]])), scale(as.numeric(gtex_tcga[[gene_name]])), scale(as.numeric(mayo_tcga[[gene_name]])))
  colnames(expression_concat) = c("TCGA_NORMAL","GTEX", "MAYO")

  if( length(unique(expression_concat$TCGA_NORMAL)) == 1 || length(unique(expression_concat$GTEX)) == 1 || length(unique(expression_concat$MAYO)) == 1 ){
    print(paste("Skipping", gene_name, sep=" "))
    next
  }

  print(gene_name)

  results = glm(TCGA_NORMAL ~ MAYO, data = expression_concat)
  mayo_vs_tcga_model = summary(results)
  ssr = sum(residuals(results)^2)

  spearman = cor.test(expression_concat$TCGA_NORMAL, expression_concat$MAYO, method="spearman")
  rho = spearman$estimate

  if( !exists("mayo_vs_tcga") ){
    mayo_vs_tcga = data.frame(gene=character(), spearmans_rho=double(), effect=double(), stderr=double(), pval=double(), mse=double())
    mayo_vs_tcga_row = data.frame(gene=as.character(gene_name), spearmans_rho=rho, effect=mayo_vs_tcga_model$coefficients[2,1], stderr=mayo_vs_tcga_model$coefficients[2,2], pval=mayo_vs_tcga_model$coefficients[2,4], mse=ssr)
    mayo_vs_tcga = rbind(mayo_vs_tcga, mayo_vs_tcga_row)
  } else {
    mayo_vs_tcga_row = data.frame(gene=as.character(gene_name), spearmans_rho=rho, effect=mayo_vs_tcga_model$coefficients[2,1], stderr=mayo_vs_tcga_model$coefficients[2,2], pval=mayo_vs_tcga_model$coefficients[2,4], mse=ssr)
    mayo_vs_tcga = rbind(mayo_vs_tcga, mayo_vs_tcga_row)
  }
  
  results = glm(TCGA_NORMAL ~ GTEX, data = expression_concat)
  gtex_vs_tcga_model = summary(results)
  ssr = sum(residuals(results)^2)

  spearman = cor.test(expression_concat$TCGA_NORMAL, expression_concat$GTEX, method="spearman")
  rho = spearman$estimate

  if( !exists("gtex_vs_tcga") ){
    gtex_vs_tcga = data.frame(gene=character(), spearmans_rho=double(), effect=double(), stderr=double(), pval=double(), mse=double())
    gtex_vs_tcga_row = data.frame(gene=gene_name, spearmans_rho=rho, effect=gtex_vs_tcga_model$coefficients[2,1], stderr=gtex_vs_tcga_model$coefficients[2,2], pval=gtex_vs_tcga_model$coefficients[2,4], mse=ssr)
    gtex_vs_tcga = rbind(gtex_vs_tcga, gtex_vs_tcga_row)
  } else {
    gtex_vs_tcga_row = data.frame(gene=gene_name, spearmans_rho=rho, effect=gtex_vs_tcga_model$coefficients[2,1], stderr=gtex_vs_tcga_model$coefficients[2,2], pval=gtex_vs_tcga_model$coefficients[2,4], mse=ssr)
    gtex_vs_tcga = rbind(gtex_vs_tcga, gtex_vs_tcga_row)
  }

  results = glm(GTEX ~ MAYO, data = expression_concat)
  mayo_vs_gtex_model = summary(results)
  ssr = sum(residuals(results)^2)

  spearman = cor.test(expression_concat$TCGA_NORMAL, expression_concat$MAYO, method="spearman")
  rho = spearman$estimate

  if( !exists("mayo_vs_gtex") ){
    mayo_vs_gtex = data.frame(gene=character(), spearmans_rho=double(), effect=double(), stderr=double(), pval=double(), mse=double())
    mayo_vs_gtex_row = data.frame(gene=gene_name, spearmans_rho=rho, effect=mayo_vs_gtex_model$coefficients[2,1], stderr=mayo_vs_gtex_model$coefficients[2,2], pval=mayo_vs_gtex_model$coefficients[2,4], mse=ssr)
    mayo_vs_gtex = rbind(mayo_vs_gtex, mayo_vs_gtex_row)
  } else {
    mayo_vs_gtex_row = data.frame(gene=gene_name, spearmans_rho=rho, effect=mayo_vs_gtex_model$coefficients[2,1], stderr=mayo_vs_gtex_model$coefficients[2,2], pval=mayo_vs_gtex_model$coefficients[2,4], mse=ssr)
    mayo_vs_gtex = rbind(mayo_vs_gtex, mayo_vs_gtex_row)
  }

}

write.table(mayo_vs_tcga, file=paste(output_pre, "mayo_vs_tcga", "txt", sep="."), row.names=F, quote=F, sep="\t")
write.table(gtex_vs_tcga, file=paste(output_pre, "gtex_vs_tcga", "txt", sep="."), row.names=F, quote=F, sep="\t")
write.table(mayo_vs_gtex, file=paste(output_pre, "mayo_vs_gtex", "txt", sep="."), row.names=F, quote=F, sep="\t")

module pdbTool
	
	# Personal Belongings
	if isfile("/home/christoph/polito/ppi/scripts/stdInc.jl")
                include("/home/christoph/polito/ppi/scripts/stdInc.jl")
        end

        scriptDir="/home/christoph/polito/ppi/scripts"
        if !isdir(scriptDir)
                warn("ScriptDir not set correctly!")
        end

	######################################################################	
	# TYPE DEFINITIONS
	######################################################################	
	type Atom
	        identifier::Int64
		coordinates::(Float64,Float64,Float64)
	end
	type Residue
		aminoAcid::String
	        atom::Dict{String,Atom}
		pdbPos::Int64
		alignmentPos::Int64
		identifier::String
		naccess::Float64
		naccess_rel::Float64
		Residue(aa,pp,id)=new(aa,Dict{String,Atom}(),pp,-1,id,-1.0,-1.0)
	end
	type Strand
		identifier::Int64
		startRes::String
		endRes::String
		sense::Int64
		bondThis::String
		bondPrev::String
		Strand(identifier::Int64,startRes::String,endRes::String,sense::Int64,bondThis::String,bondPrev::String)=new(identifier::Int64,startRes::String,endRes::String,sense::Int64,bondThis::String,bondPrev::String)
	end
	type Sheet
		identifier::String
		strand::Dict{Int64,Strand}
		Sheet(identifier::String)=new(identifier,Dict{Int64,Strand}())
	end
	type Helix
		startRes::String
		endRes::String
		identifier::String
		Helix(sR,eR,id)=new(sR,eR,id)
	end
	type Chain
	        residue::Dict{String,Residue}
	        length::Int64
		mappedTo::String
		identifier::String
		align::Dict{Int64,Residue}
		helix::Dict{String,Helix}
		sheet::Dict{String,Sheet}
		isRNA::Bool
	        Chain()=new(Dict{String,Residue}(),0,"","",Dict{Int64,Residue}(),Dict{String,Helix}(),Dict{String,Sheet}(),false)
	end
	type Pdb
	        chain::Dict{String,Chain}
	        pdbName::String
	        fileName::String
	        Pdb()=new(Dict{String,Chain}(),"","")
	end

	######################################################################	
	# FUNCTION:		 parsePdb             	
	######################################################################	
	function parsePdb(pdbFile::String="/home/christoph/polito/ppi/data/pdb/2Z4K.pdb")
		pdb=Pdb()
		for l in eachline(open(pdbFile))
			if l[1:4]=="ATOM" && (l[17]==' ' || l[17]=='A')
				ch=strip(l[22:22])
				res=strip(l[23:27])
				if !haskey(pdb.chain,ch)
					pdb.chain[ch]=Chain()
					pdb.chain[ch].identifier=ch
					if length(lstrip(l[18:20]))<3
						pdb.chain[ch].isRNA=true
						println("Chain $ch treated as RNA")
					end
				end
				if !haskey(pdb.chain[ch].residue,res)
					pdb.chain[ch].length += 1
					pdb.chain[ch].residue[res]=Residue(l[18:20],pdb.chain[ch].length,res)
				end
				pdb.chain[ch].residue[res].atom[strip(l[13:16])]=Atom(int(l[7:11]),(float(l[31:38]),float(l[39:46]),float(l[47:54])))
				if pdb.chain[ch].isRNA
					for res in values(pdb.chain[ch].residue)
						res.aminoAcid=lstrip(res.aminoAcid)
					end
				end

				
			end
			if l[1:5]=="HELIX"
				ch=strip(l[20:20])
				hel=strip(l[12:14])
				if !haskey(pdb.chain,ch)
					pdb.chain[ch]=Chain()
					pdb.chain[ch].identifier=ch
					if length(lstrip(l[18:20]))<3
						pdb.chain[ch].isRNA=true
						println("Chain $ch treated as RNA")
					end
				end
				if haskey(pdb.chain[ch].helix,hel)
					error("Found the same helix twice and panicked")
				end
				pdb.chain[ch].helix[hel]=Helix(strip(l[22:26]),strip(l[34:38]),hel)
			end
			if l[1:5]=="SHEET"
				if l[22:22]!=l[33:33]
					warn("PDB contains sheets across several chains - ignoring them for now!")
					continue
				end
				ch=strip(l[22:22])
				sh=strip(l[12:14])
				str=int(strip(l[8:10]))
				if !haskey(pdb.chain,ch)
					pdb.chain[ch]=Chain()
					pdb.chain[ch].identifier=ch
					if length(lstrip(l[18:20]))<3
						pdb.chain[ch].isRNA
						println("Chain $ch treated as RNA")
					end
				end
				if !haskey(pdb.chain[ch].sheet,sh)
					pdb.chain[ch].sheet[sh]=Sheet(sh)
				end
				if haskey(pdb.chain[ch].sheet[sh].strand,str)
					error("Found the same strand twice and panicked")
				end
				sense=int(l[39:40])
				if sense!=0
					pdb.chain[ch].sheet[sh].strand[str]=Strand(str,strip(l[23:27]),strip(l[34:38]),sense,strip(l[51:55]),strip(l[66:70]))
				else
					pdb.chain[ch].sheet[sh].strand[str]=Strand(str,strip(l[23:27]),strip(l[34:38]),sense,"","")
				end
			end
					
		end
		return pdb;
	end




	######################################################################	
	# FUNCTION:		 atomDist             	
	######################################################################	
	function atomDist(atom1::Atom, atom2::Atom)
			return sqrt((atom1.coordinates[1]-atom2.coordinates[1])^2 + (atom1.coordinates[2] - atom2.coordinates[2])^2 + (atom1.coordinates[3] - atom2.coordinates[3])^2)
	end

	######################################################################	
	# FUNCTION:		 residueDist
	######################################################################	
	function residueDist(res1::Residue, res2::Residue; distType="heavyMin")
		if distType=="heavyMin"
			d=Inf
			for atom1 in values(res1.atom)
				for atom2 in values(res2.atom)	
					d=min(d,atomDist(atom1,atom2))
				end
			end
			return d
		end
		if distType=="ca"
			if haskey(res1.atom,"CA") && haskey(res2.atom,"CA")
				return atomDist(res1.atom["CA"],res2.atom["CA"])
			else
			 	error("error calculating distances: Residues do not have CA entries")
			end
		end
		error("Error calculating distances: supported types are heavyMin or ca")
	end

	######################################################################	
	# FUNCTION:		 chainDist
	######################################################################	
	function chainDist(ch1::Chain, ch2::Chain,out="undef")
		if out=="undef"
			for r1=sort([k for k in keys(ch1.residue)])
				for r2=sort([k for k in keys(ch2.residue)])
					@printf("%s %s %f\n", r1, r2, residueDist(ch1.residue[r1],ch2.residue[r2]))
				end
			end
		else 
			fid=open(out,"w")
			for r1=sort([k for k in keys(ch1.residue)])
				for r2=sort([k for k in keys(ch2.residue)])
					@printf(fid,"%s %s %f\n", r1, r2, residueDist(ch1.residue[r1],ch2.residue[r2]))
				end
			end
		end
	end

	######################################################################	
	# FUNCTION:		 interAlignDist
	######################################################################	
	function interAlignDist(ch1::Chain, ch2::Chain;out="undef")
		if ch1.mappedTo==""
			error("chain 1 not mapped")
		end
		if ch2.mappedTo==""
			error("chain 2 not mapped")
		end
		LENG1=getHmmLength(ch1.mappedTo)
		LENG2=getHmmLength(ch2.mappedTo)
		completeAlign=Dict{Int64,Residue}()
		for i in keys(ch1.align)
			completeAlign[i]=ch1.align[i]
		end
		for i in keys(ch2.align)
			completeAlign[i+LENG1]=ch2.align[i]
		end
		ind=sort([x for x in keys(completeAlign)])
		if out=="undef"
			for i=1:length(ind)
				for j=(i+1):length(ind)
					@printf("%s %s %f\n", ind[i], ind[j], residueDist(completeAlign[ind[i]],completeAlign[ind[j]]))
				end
			end
		else 
			fid=open(out,"w")
			for i=1:length(ind)
				for j=(i+1):length(ind)
					@printf(fid,"%s %s %f\n", ind[i], ind[j], residueDist(completeAlign[ind[i]],completeAlign[ind[j]]))
				end
			end
			close(fid)
		end
	end
	######################################################################	
	# FUNCTION:		 chainSeq
	######################################################################	
	function chainSeq(chain)
		# Unordered pdbSeq
		if !chain.isRNA
			pdbSeq=[aminoAcidDict[chain.residue[k].aminoAcid] for k in keys(chain.residue)]
		else
			pdbSeq=[chain.residue[k].aminoAcid for k in keys(chain.residue)]
		end

		ind=sortperm([chain.residue[k].pdbPos for k in keys(chain.residue)])
		return join(pdbSeq[ind])
	end
	
	######################################################################	
	# FUNCTION:		 mapChainToHmm
	######################################################################	
	function mapChainToHmm(chain,hmmFile)
		# Check if the chain already has a mapping - and delete it if yes
		if chain.mappedTo!=""
			println("chain $(chain.identifier) already has a mapping.")
		end
		
		# Actual mapping
		pdbSeq=chainSeq(chain)
		tempFile=tempname()
		fid=open(tempFile,"w")
		@printf(fid,">temp\n%s",pdbSeq)
		close(fid)
		if !chain.isRNA
			run(`hmmalign $hmmFile $tempFile` |> "$tempFile.out")
		else
			run(`cmsearch -A $tempFile.out $hmmFile $tempFile` |> DevNull)
		end
		align=[split(readall(`$scriptDir/stockholm2fasta $tempFile.out`),'\n')]	
		rm("$tempFile"); rm("$tempFile.out")
		pdbIndices=find([align[2][x]!='-' for x=1:length(align[2])]) 
		cleanIndices=find(![islower(align[2][x]) for x=1:length(align[2])])
		fakeAlign2pdb=-ones(Int64,length(align[2]))
		fakeAlign2pdb[pdbIndices]=[1:length(pdbSeq)]
		align2pdb=fakeAlign2pdb[cleanIndices]
		for k in keys(chain.residue)
			if chain.residue[k].pdbPos > 0
				x=find(align2pdb.==chain.residue[k].pdbPos)
				if length(x)>1
					error("found several pdb positions")
				end
				if length(x)==1
					chain.residue[k].alignmentPos=x[1]
					chain.align[x[1]]=chain.residue[k]
				end
			end
		end	
		chain.mappedTo=hmmFile
	end

	######################################################################	
	# FUNCTION:		 mapChainToHmmLegacy
	######################################################################	
	function mapChainToHmmLegacy(chain,hmmFile)
		println("LEGACY MAPPING ACTIVE")
		# Check if the chain already has a mapping - and delete it if yes
		if chain.mappedTo!=""
			println("chain $(chain.identifier) already has a mapping.")
		end
		
		# Actual mapping
		pdbSeq=chainSeq(chain)
		tempFile=tempname()
		fid=open(tempFile,"w")
		@printf(fid,">temp\n%s",pdbSeq)
		close(fid)
		if !chain.isRNA
			run(`hmmsearch -A $tempFile.out $hmmFile $tempFile` |> DevNull)
		else
			run(`cmsearch -A $tempFile.out $hmmFile $tempFile` |> DevNull)
		end
		align=[split(readall(`$scriptDir/stockholm2fasta $tempFile.out`),'\n')]	
		rm("$tempFile"); rm("$tempFile.out")
		(pdbStart,pdbStop)=int(matchall(r"\d+",align[1]))
		pdbIndices=find([align[2][x]!='-' for x=1:length(align[2])]) 
		cleanIndices=find(![islower(align[2][x]) for x=1:length(align[2])])
		fakeAlign2pdb=-ones(Int64,length(align[2]))
		fakeAlign2pdb[pdbIndices]=[pdbStart:pdbStop]
		align2pdb=fakeAlign2pdb[cleanIndices]
		for k in keys(chain.residue)
			if chain.residue[k].pdbPos > 0
				x=find(align2pdb.==chain.residue[k].pdbPos)
				if length(x)>1
					error("found several pdb positions")
				end
				if length(x)==1
					chain.residue[k].alignmentPos=x[1]
					chain.align[x[1]]=chain.residue[k]
				end
			end
		end	
		chain.mappedTo=hmmFile
	end

	######################################################################	
	# FUNCTION:		 intraAlignDist
	######################################################################	
	function intraAlignDist(chain::Chain,out="distMat")
		if out=="distMat"
			if chain.mappedTo=="" 
				error("chain has no mapping")
			end
			LENG=getHmmLength(chain.mappedTo)	
			distMat=-ones(LENG,LENG)
			for k1 in keys(chain.residue)
				for k2 in keys(chain.residue)
					if k1==k2
						continue
					end
					r1=chain.residue[k1]
					r2=chain.residue[k2]
					if r1.alignmentPos > 0 && r2.alignmentPos > 0
						distMat[r1.alignmentPos,r2.alignmentPos] = residueDist(r1,r2)
					end
				end
			end
		end
		return distMat
	end

	######################################################################	
	# FUNCTION:		 makeIntraRoc
	######################################################################	
	function makeIntraRoc(score::Array{(Int64,Int64,Float64),1},chain::Chain;sz=200,cutoff::Float64=8.0,out::String="return",pymolMode::Bool=false,minSeparation::Int64=4)
		if chain.mappedTo==""
			error("chain has no mapping")
		end
		if out!="return"
			fid=open(out)
		end
		if !pymolMode
			roc=Array((String,String,Float64,Float64),sz)
		else
			roc=Array((String,String,Int64),sz)
		end
			s::Int64=0
			i::Int64=0
			hits::Int64=0
			while s<sz
				i+=1
				if abs(score[i][1]-score[i][2]) <= minSeparation 
					continue
				end
				if haskey(chain.align,score[i][1]) && haskey(chain.align,score[i][2])
					s+=1
					if residueDist(chain.align[score[i][1]],chain.align[score[i][2]])<cutoff
						hits+=1
						if pymolMode
							x=1
						else 
							x=hits/s	
						end
					else
						x=hits/s
						if pymolMode
							x=0
						end
					end
					roc[s]=(chain.align[score[i][1]].identifier,chain.align[score[i][2]].identifier,x,score[i][3])
				end
			end
		return roc
	end

	######################################################################	
	# FUNCTION:		 filterInterScore
	######################################################################	
	function filterInterScore(score::Array{(Int64,Int64,Float64),1},chain1::Chain,chain2::Chain;sz=200,cutoff::Float64=8.0,out::String="return")

		# Check if mapping is existent
		if chain1.mappedTo == ""
				error("chain 1 has no mapping")
		elseif chain2.mappedTo == ""
				error("chain 2 has no mapping")
		end
		LENG1=getHmmLength(chain1.mappedTo)
		LENG2=getHmmLength(chain2.mappedTo)

		if out=="return"
			newScore=Array((String,String,Float64),sz)
			s::Int64=0
			i::Int64=0
			hits::Int64=0
			positives::Int64=0
			while s<sz && i<size(score,1)
				i+=1
				if score[i][1] <= LENG1 && score[i][2] > LENG1
					ind1=score[i][1]
					ind2=score[i][2]-LENG1
				elseif score[i][2] <= LENG1 && score[i][1] > LENG1
					ind1=score[i][2]
					ind2=score[i][1]-LENG1
				else
					continue
				end
				if haskey(chain1.align,ind1) && haskey(chain2.align,ind2)
					s+=1
					id1=chain1.align[ind1].identifier
					id2=chain2.align[ind2].identifier
					newScore[s]=(id1,id2,score[i][3])
				end
			end
			return newScore
		end
	end
	function filterInterScore(score::Array{(Int64,Int64,Float64),1},hmm1::String,hmm2::String;sz=200,cutoff::Float64=8.0,out::String="return")

		# Check if mapping is existent
		LENG1=getHmmLength(hmm1)	
		LENG2=getHmmLength(hmm2)

		if out=="return"
			interScore=Array((Int64,Int64,Float64),0)
			score1=Array((Int64,Int64,Float64),0)
			score2=Array((Int64,Int64,Float64),0)

			s::Int64=0
			i::Int64=0
			hits::Int64=0
			positives::Int64=0
			for i=1:length(score)
				
				if score[i][1] <= LENG1 && score[i][2] > LENG1
					ind1=score[i][1]
					ind2=score[i][2]-LENG1
					push!(interScore,(ind1,ind2,score[i][3]))

				elseif score[i][2] <= LENG1 && score[i][1] > LENG1
					ind1=score[i][2]
					ind2=score[i][1]-LENG1
					push!(interScore,(ind1,ind2,score[i][3]))

				elseif score[i][1] <= LENG1 && score[i][2] <= LENG1
					ind1=score[i][1]
					ind2=score[i][2]
					push!(score1,(ind1,ind2,score[i][3]))

				elseif score[i][1] > LENG1 && score[i][2] > LENG1
					ind1=score[i][1]-LENG1
					ind2=score[i][2]-LENG1
					push!(score2,(ind1,ind2,score[i][3]))
				end
			end
			return interScore,score1,score2
		end
	end

	######################################################################	
	# FUNCTION:		 makeInterRoc
	######################################################################	
	function makeInterRoc(score::Array{(Int64,Int64,Float64),1},chain1::Chain,chain2::Chain;sz=200,cutoff::Float64=8.0,out::String="return",pymolMode::Bool=false,naccessRatio::Float64=1.0)

		# Check if mapping is existent
		if chain1.mappedTo == ""
				error("chain 1 has no mapping")
		elseif chain2.mappedTo == ""
				error("chain 2 has no mapping")
		end
		LENG1=getHmmLength(chain1.mappedTo)
		LENG2=getHmmLength(chain2.mappedTo)

		# Get naccess cutoff if necessary
		if naccessRatio<1.0
			naList1=zeros(LENG1);
			naList2=zeros(LENG2);
			i=1;
			for r1 in values(chain1.align)
				naList1[i]=r1.naccess;
				i+=1;
			end
			i=1;
			for r2 in values(chain2.align)
				naList2[i]=r2.naccess;
				i+=1;
			end
			naList1=sort(naList1,rev=true);
			na1Cutoff=naList1[int(round(LENG1*naccessRatio))];
			println(na1Cutoff)
			naList2=sort(naList2,rev=true);
			na2Cutoff=naList2[int(round(LENG2*naccessRatio))];
			println(na2Cutoff)
		end

		if out=="return"
			roc=Array((String,String,Float64,Float64),sz)
			s::Int64=0
			i::Int64=0
			hits::Int64=0
			positives::Int64=0
			while s<sz && i<size(score,1)
				i+=1
				if score[i][1] <= LENG1 && score[i][2] > LENG1
					ind1=score[i][1]
					ind2=score[i][2]-LENG1
				elseif score[i][2] <= LENG1 && score[i][1] > LENG1
					ind1=score[i][2]
					ind2=score[i][1]-LENG1
				else
					continue
				end
				if haskey(chain1.align,ind1) && haskey(chain2.align,ind2)
					if naccessRatio<1.0
						if chain1.align[ind1].naccess<na1Cutoff || chain2.align[ind2].naccess<na2Cutoff
							continue;
						end
					end
					s+=1
					id1=chain1.align[ind1].identifier
					id2=chain2.align[ind2].identifier
					if residueDist(chain1.align[ind1],chain2.align[ind2])<cutoff
						hits+=1
						if pymolMode
							hits=s
						end
						roc[s]=(id1,id2,hits/s,score[i][3])
					else
						if pymolMode
							hits=0
						end
						roc[s]=(id1,id2,hits/s,score[i][3])
					end
				end
			end
			return roc
		end
	end

	######################################################################	
	# FUNCTION:		 getHmmLength(hmmFile)
	######################################################################	
	function getHmmLength(hmmFile)
		for l in eachline(open(hmmFile))
			if l[1:4] == "LENG" || l[1:4]=="CLEN"
				LENG::Int64=int(match(r"\d+",l).match)
				return LENG
			end
		end
		error("unable to get hmm length in $hmmFile")
	end

	######################################################################	
	# FUNCTION:		 makeMarriedContactMap(chain1,chain2)
	######################################################################	
	## IDIOCY: THIS DOES THE SAME THING AS THE FUNCTION "interAlignDist"
	function makeMarriedContactMap(chain1,chain2;output::String="default")
		chain1map=chain1.mappedTo
		chain2map=chain2.mappedTo
		chain1map=="" && error("chain $(chain1.identifier) has no mapping")
		chain2map=="" && error("chain $(chain2.identifier) has no mapping")
		LENG1=getHmmLength(chain1map)
		LENG2=getHmmLength(chain2map)
		contactMap=-ones(Float64,LENG1+LENG2,LENG1+LENG2)
		# Protein 1
		for r1 in values(chain1.align)
			for r2 in values(chain1.align)
				r1.alignmentPos==-1 && error("incoherent alignment information")
				r2.alignmentPos==-1 && error("incoherent alignment information")
				contactMap[r1.alignmentPos,r2.alignmentPos]=residueDist(r1,r2)
			end
		end
		# Protein 2
		for r1 in values(chain2.align)
			for r2 in values(chain2.align)
				r1.alignmentPos==-1 && error("incoherent alignment information")
				r2.alignmentPos==-1 && error("incoherent alignment information")
				contactMap[r1.alignmentPos+LENG1,r2.alignmentPos+LENG1]=residueDist(r1,r2)
			end
		end
		# Protein 1 - Protein 2
		for r1 in values(chain1.align)
			for r2 in values(chain2.align)
				r1.alignmentPos==-1 && error("incoherent alignment information")
				r2.alignmentPos==-1 && error("incoherent alignment information")
				d=residueDist(r1,r2)
				contactMap[r1.alignmentPos,r2.alignmentPos+LENG1]=d
				contactMap[r2.alignmentPos+LENG1,r1.alignmentPos]=d
			end
		end
		if output!="default"
			fid=open(output,"w")	
			for i=1:LENG1+LENG2
				for j=(i+1):LENG1+LENG2
					contactMap[i,j]<0.0 && continue
					@printf(fid,"%d\t%d\t%f\n",i,j,contactMap[i,j])
				end
			end
			close(fid)
		end
		return contactMap
		
		
	end


	######################################################################	
	# FUNCTION:		 countContacts(chain)
	######################################################################	
	function countContacts(chain;min_separation=5,cutoff=8.0)
		nums=sort([n for n in keys(chain.align)])
		contacts=0
		for i=1:length(nums)
			for j=(i+1):length(nums)	
				id1=nums[i]
				id2=nums[j]
				if abs(id1-id2)<min_separation
					continue
				end
				res1=chain.align[id1]
				res2=chain.align[id2]
				if res1.alignmentPos<1 || res2.alignmentPos<1
					error("Something went horribly wrong here")
				end
				d=pdbTool.residueDist(res1,res2)
				if d<cutoff
					contacts=contacts+1
				end
			end
		end
		return contacts
	end
	######################################################################	
	# FUNCTION:		 interactionSurface(chain1,chain2)
	######################################################################	
	function interactionSurface(chain1,chain2;numbersOnly::Bool=true,alignedOnly::Bool=true,cutoff::Float64=8.0)
		if chain1.mappedTo=="" || chain2.mappedTo==""
			error("At least one chain not mapped")
		end
		pdbPairs=0;
		alignmentPairs=0;
		if !numbersOnly
			iS=Array((String,String),0)
		end
		for r1 in values(chain1.residue)
			for r2 in values(chain2.residue)
				if residueDist(r1,r2)<cutoff
					pdbPairs+=1;
					if !numbersOnly && !alignedOnly
						push!(iS,(r1.identifier,r2.identifier))
					end
					if r1.alignmentPos>0 && r2.alignmentPos>0
						alignmentPairs+=1;
						if !numbersOnly && alignedOnly
							push!(iS,(r1.identifier,r2.identifier))
						end
					end

				end
			end
		end
		if numbersOnly
			return pdbPairs,alignmentPairs
		else
			return iS
		end
						
	end
	 ######################################################################  
        # DATA:          aminoAcidChainDict
        ######################################################################  

        #http://www.uniprot.org/manual/non_std;Selenocysteine (Sec) and pyrrolysine (Pyl)
        aminoAcidDict=Dict{String,String}()
        aminoAcidDict["ALA"]="A";
        aminoAcidDict["ARG"]="R";
        aminoAcidDict["ASN"]="N";
        aminoAcidDict["ASP"]="D";
        aminoAcidDict["CYS"]="C";
        aminoAcidDict["GLU"]="E";
        aminoAcidDict["GLN"]="Q";
        aminoAcidDict["GLY"]="G";
        aminoAcidDict["HIS"]="H";
        aminoAcidDict["ILE"]="I";
        aminoAcidDict["LEU"]="L";
        aminoAcidDict["LYS"]="K";
        aminoAcidDict["MET"]="M";
        aminoAcidDict["PHE"]="F";
        aminoAcidDict["PRO"]="P";
        aminoAcidDict["SER"]="S";
        aminoAcidDict["THR"]="T";
        aminoAcidDict["TRP"]="W";
        aminoAcidDict["TYR"]="Y";
        aminoAcidDict["VAL"]="V";
        aminoAcidDict["SEC"]="U";
        aminoAcidDict["PYL"]="O";
	
				

	######### PARSE HELPERS
	function parseRibosome(;blits::Bool=false,largeOnly::Bool=false,smallOnly::Bool=false,legacyMapping::Bool=false)
		println("THIS IS A FUNCTION THAT WORKS ONLY ON MY DIRECTORY STRUCTURE")
		pdbSmall=parsePdb("/home/christoph/polito/ppi/data/pdb/2Z4K.pdb")
		if !smallOnly
			pdbLarge=parsePdb("/home/christoph/polito/ppi/data/pdb/2Z4L.pdb")
		end
		println("Parsed PDBs, doing mapping")
		if !blits
			for k in keys(pdbSmall.chain)
				if pdbSmall.chain[k].isRNA==true
					continue
				end
				println("Mapping Small Subunit, chain $k")	
				id=invSmallRiboChainDict[k]
				mapFile="/home/christoph/polito/ppi/data/FINAL_SMALL/RS$id/RS$id.names.blastdb.mafft.ungap.hmmbuild"
				if !legacyMapping
					mapChainToHmm(pdbSmall.chain[k],mapFile)
				else
					mapChainToHmmLegacy(pdbSmall.chain[k],mapFile)
				end
				#	# Get the naccess values
				#	try
				#	x=readdlm("/home/christoph/polito/ppi/data/FINAL_SMALL/naccess/RS$(id)_align.rsa",' ')
				#	for i=1:size(x,1)
				#		if x[i,3]>0
				#			pdbSmall.chain[k].align[int(x[i,1])].naccess=x[i,3]
				#		end
				#	end
				#	catch
				#		println("No naccess for RS$id !")
				#	end
				#	try
				#	x=readdlm("/home/christoph/polito/ppi/data/FINAL_SMALL/naccess/RS$(id)_align_rel.rsa",' ')
				#	for i=1:size(x,1)
				#		if x[i,3]>0
				#			pdbSmall.chain[k].align[int(x[i,1])].naccess_rel=x[i,3]
				#		end
				#	end
				#	catch
				#		println("No naccess for RS$id !")
				#	end
			end
			println("Mapping Small Subunit, Chain A (RNA)")
			mapChainToHmm(pdbSmall.chain["A"],"/home/christoph/polito/ppi/data/rna/RF00177.cm")
			if !smallOnly
			for k in keys(pdbLarge.chain)
				if pdbLarge.chain[k].isRNA==true
					continue
				end
				println("Mapping Large Subunit, chain $k")	
				if haskey(invLargeRiboChainDict,k)
					 id=invLargeRiboChainDict[k]
				else
				  	 println("Chain $k not in dictionary!")
					 continue
				end
				mapFile="/home/christoph/polito/ppi/data/FINAL_LARGE/RALL/RL$id.fasta.names.blastdb.mafft.ungap.hmmbuild"
				if !isfile(mapFile)
					println("No mapfile for $k")
					continue
				end
				if !legacyMapping
					mapChainToHmm(pdbLarge.chain[k],mapFile)
				else
					mapChainToHmmLegacy(pdbLarge.chain[k],mapFile)
				end
			end
			end
		end
		if blits
			for ch in values(pdbSmall.chain)
				ch.mappedTo="blits"
				for res in values(ch.residue)
					res.alignmentPos=res.pdbPos;
					ch.align[res.alignmentPos]=res;
				end
			end
		end
	
		if !smallOnly
			return pdbSmall,pdbLarge;
		else
			return pdbSmall
		end
	end

	function parseArchs()
		pdbArch=Array(Dict{String,Pdb},9)
		fid=open("/home/christoph/polito/ppi/data/gtpase/pdb/pdbList","r")
		for line in eachline(fid)
			id=int(match(r"^\d",line).match)
			hmm="/home/christoph/polito/ppi/data/gtpase/arch$id/arch$id.names.blastdb.mafft.ungap.hmmbuild"
			if id==3
				hmm="/home/christoph/polito/ppi/data/gtpase/arch$id/arch$id.names.filtered.blastdb.mafft.ungap.hmmbuild"
			end
			!isfile(hmm) && continue
			m=matchall(r"\d[A-Z,0-9]{3}",line)
			pdbArch[id]=Dict{String,Pdb}()
			for name in m
				pdb=parsePdb("/home/christoph/polito/ppi/data/gtpase/pdb/pdb$(lowercase(name)).ent")
				mapChainToHmm(pdb.chain["A"],hmm)
				pdbArch[id][lowercase(name)]=pdb
			end
		end
		return pdbArch
	end
end

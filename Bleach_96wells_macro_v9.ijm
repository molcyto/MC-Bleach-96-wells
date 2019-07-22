// ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// Copyright (C) 2019  Dorus Gadella
// electronic mail address: th #dot# w #dot# j #dot# gadella #at# uva #dot# nl
// 
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
// 
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.
// ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//
//measure average intensity in 96/384-wells bleach series
//writes a log file
//this text file imports into Excel (through import) and generates for each well a column with 25 time points x2
//created input dialog and optional output of multiwell images representing T50% and remaining fluorescence
//
//============================================
//Version history:
//version1  Dorus 30-6-2014
//--------------------------------------------------
//Version2 Dorus 1-7-2014
//Assumed acquisition mode A1-A12, B12-B1, C1-C12 etc
//included option to skip 4 columns
//included option to start at any  position in a multiwell plate
//--------------------------------------------------
//Version3 Dorus 2-7-2014
//removed the option to skip columns
//expanded the macro to optional 384 well format.
//--------------------------------------------------
//Version4 Dorus 7-7-2014
//rewrote start position to start as upper left well and then move zig-zag from there
//Introduced choice to work on already loaded hyperstack or to generate one from a directory
//--------------------------------------------------
//Version5 Dorus 8-7-2014
//Introduced optional image of multiwell image of average intensity of first time point 
//Introduced printing of actual well number in output logfile
//--------------------------------------------------
//Version6 Dorus 3-2-2015
//Fixed auto display of taulow and tauhigh
//--------------------------------------------------
//Version7 Dorus 3-2-2015
//Introduced thresholding and measuring bleaching per cell
//Changed output to average bleaching per cell and standard deviation and cell number
//--------------------------------------------------
//Version8 Dorus 3-2-2015
//Introduced optional modal value per frame for background estimation
//--------------------------------------------------
//Version9 Dorus 15-7-2019
//Introduced optional meandering mode for well plate acquisition/display
//--------------------------------------------------

Dialog.create("Input dialog for Multiwell bleach analysis");
Dialog.addChoice("Work on current image or load from directory :",newArray("current image","load from directory"),"load from directory");
Dialog.addChoice("96 wells or 384 wells:",newArray("96 wells","384 wells"),"96 wells");
Dialog.addChoice("Fixed background value or modal value background",newArray("Fixed","modal"),"modal");
Dialog.addNumber("In case of fixed background the background intensity:", 108.13);
Dialog.addNumber("Threshold=number*Stdev+modal:",2);
Dialog.addCheckbox("Keep cell ROIs:", true);
Dialog.addCheckbox("Create output 96/384 well tau image:", true);
Dialog.addNumber("Low threshold for 50% time:", 0);
Dialog.addNumber("High threshold for 50% time:", 240);
Dialog.addCheckbox("Automatic determination of thresholds:", false);
Dialog.addCheckbox("Create output 96/384 well non-bleached image:", true);
Dialog.addCheckbox("Create output 96/384 well initial intensity image:", true);
row_arr=newArray("A","B","C","D", "E","F", "G","H","I","J","K","L", "M","N", "O","P")    
Dialog.addChoice("Start row:",row_arr,row_arr[2]); 
Dialog.addNumber("Start column:",9);
Dialog.addCheckbox("Acquisition in meandering mode: ",true);

Dialog.show();
openfromdir=Dialog.getChoice();
wellplate=Dialog.getChoice();
backgroundmode=Dialog.getChoice();
background= Dialog.getNumber();
thresset=Dialog.getNumber();
keepROIs=Dialog.getCheckbox();
well96=Dialog.getCheckbox();
taulow=Dialog.getNumber();
tauhigh=Dialog.getNumber();
tau_auto=Dialog.getCheckbox();
non_bl=Dialog.getCheckbox();
int_im=Dialog.getCheckbox();
srow=Dialog.getChoice();
scolumn=Dialog.getNumber();
meander=Dialog.getCheckbox();
num_wells=96;
num_rows=8;
num_columns=12;
if(wellplate=="384 wells") {
	num_wells=384;
	num_rows=16;
	num_columns=24;
}
for (i=1;i<=16;i++){
	j=i-1;
	if (srow==row_arr[j]) sro=i;
}
st=num_columns*(sro-1)+scolumn;
setBatchMode(true);

if (openfromdir=="load from directory"){
	filedir = getDirectory("Choose Source Directory ");
	list = getFileList(filedir);
	for (i=0; i<list.length; i++) {
		showProgress(i+1, list.length);
		run("Bio-Formats (Windowless)", "open=["+filedir+list[i]+"]");
// below 2 lines optional for reducing size input images in case of memory problems
//		run("Scale...", "x=.5 y=.5 z=1.0 width=976 height=976 depth=25 interpolation=Bilinear average process create");
//		close(list[i]);
		if(i==0) {
			filein=filedir+getTitle(); fname=getTitle();fileout=filein+".tiff";
			nt=nSlices();
		}
	}
	run("Concatenate...", "all_open title=[Concatenated Stacks] open");
	run("Stack to Hyperstack...", "order=xytcz channels="+list.length+" slices=1 frames="+nt+" display=Grayscale");
}else{
	filedir = getDirectory("image"); filein=filedir+getTitle(); fname=getTitle(); fileout=filein+".tiff";
}
rename("HyperStackje");
getDimensions(x,y,pos,z,nt);
numstacks=nSlices()+1;
getStatistics(npix,mean,p,q,mean_sd);
if(keepROIs==true)	newImage("CellROIs", "8-bit white", x,y,pos);
out=newArray(numstacks);
//out_ini=newArray(numstacks);
out_std=newArray(numstacks);
bg=newArray(nt);

npos=pos+1;
tau=newArray(npos);
recov=newArray(npos);
remain=newArray(npos);
init_int=newArray(npos);
cellnum=newArray(npos);
stot=st+npos;
if (stot>num_wells) {
	st=1;
	sro=1;
	scolumn=1;
}
if (pos>num_wells) exit("More positions in hyperstack than wells");
ind=newArray(385);
i=0;

for (well=1;well<=pos;well++) {
	showProgress(well);
	for (iloop=1;iloop<=z;iloop++) {
		inum=(iloop-1)*pos+well;
		selectWindow("HyperStackje");
		setSlice(inum);
//statement below copies one time lapse for one well into a separate stack (timestack)
		run("Reduce Dimensionality...", "  frames keep");
		rename("timestack");

//loop below extracts modal value in each image of the timelapse as background
		if (backgroundmode=="modal") {
			run("Set Measurements...", "  modal redirect=None decimal=9");
			for (i=1;i<=nt;i++) {
				setSlice(i);
				run("Measure");
			}
			for (i=1;i<=nt;i++) {
				bg[i-1]=getResult("Mode",i-1);
			}
			run("Clear Results");
		}else{
			for (i=1;i<=nt;i++) {
				bg[i-1]=background;
			}
		}
		run("Set Measurements...", "  mean standard modal min redirect=None decimal=9");
		selectWindow("timestack");

		setSlice(1);

		run("Measure");
		headings = split(String.getResultsHeadings);
		mod=getResult(headings[2],0);
		std=getResult(headings[1],0);
		max=getResult(headings[4],0);

//the median pixel value (usually background) is determined (mod) and the standard deviation of pixel values in the image is determined (stdev)
		selectWindow("Results");
		run("Close");
// The lower analysis threshold is set to the modal pixel value of the image (is usually background)+thresset x the standard deviation within the imge
		threslow=mod+thresset*std;

		threshigh=65000;
//		print(mod,std, max, threslow, threshigh);

		selectWindow("timestack");

		setThreshold(threslow,threshigh);
		setThreshold(threslow,threshigh);
		setThreshold(threslow,threshigh);
		roiManager("reset"); 
		run("Set Measurements...", "  mean redirect=None decimal=9");
		run("Analyze Particles...", "size=40-Infinity circularity=0.00-1.00 show=Nothing add slice");
		roiManager("Show All");
		roiManager("Multi Measure");
//The above 3 lines use the thresholded image of the first time point to analyze the whole time stack
// and produce a result image with for every object (cell) an average intensity per frame
		if (nResults >0){
			selectWindow("Results");
//The lines below takes the results out of the result image window. First it analyzes the number of columns (=cells) in the results window
			headings = split(String.getResultsHeadings);
			cellcount=lengthOf(headings);
			if (cellcount>0){
				init_inte=newArray(cellcount);
//Below the initial intensity per well is copied
				for (col=0; col<cellcount; col++) {
			    		init_inte[col]=getResult(headings[col],0)-bg[0] ;
					init_int[well]=init_int[well]+init_inte[col];
			  	}
				cellnum[well]=cellcount;
				init_int[well]=init_int[well]/cellcount;
//Below all time points are copied per cell (each row in the result image is a time point, each column is a cell).
			  	for (row=0; row<nResults; row++) {
			     		line = "";
					inum=row*z*pos+(iloop-1)*pos+well;
					sumvalue=0;sumvalue2=0;
			     		for (col=0; col<cellcount; col++) {
				 		value=getResult(headings[col],row);
						value=100*(value-bg[row])/(init_inte[col]);
						sumvalue=sumvalue+value;
						sumvalue2=sumvalue2+value*value;
					}
					valuemean=sumvalue/cellcount;
					valuestd=sqrt(sumvalue2/cellcount-valuemean*valuemean);
					out[inum]=value;
					out_std[inum]=valuestd;
					if (row==0) out_std[inum]=0;
				}	
			}
			run("Clear Results");
			selectWindow("Results");
			run("Close");
		}else{
			cellnum[well]=0;
			init_int[well]=0;
			for (i=1;i<=nt;i++) {
				inum=(i-1)*z*pos+(iloop-1)*pos+well;
				out[inum]=0;
				out_std[inum]=0;

				bg[i-1]=0;
			}
		}
		selectWindow("timestack");
//Below the cell mask is copied into a new image array
		if (keepROIs==true) {
			setSlice(1);
			run("Analyze Particles...", "size=40-Infinity circularity=0.00-1.00 show=Masks slice");
			run("Copy");
			run("Close");
			selectWindow("CellROIs");
			setSlice(well);
			run("Paste");
		}
		selectWindow("timestack");
		run("Close");
	}
}



taulowest=100000000;
tauhighest=0;

itothigh=0;
for (well=1;well<=pos;well++) {
	if (init_int[well] > itothigh) itothigh=init_int[well];
	iloop=1;
	i50=0;
	for (t=1;t<=nt;t++) {
		inum=(t-1)*z*pos+(iloop-1)*pos+well;
		if(out[inum]>50) i50=i50+1;
	}
	if(i50>=nt) { 
		inum1=(nt-1)*z*pos+(iloop-1)*pos+well;
		tau[well]=nt*out[inum]/50;
	}else{		
		if(i50==0) {
			tau[well]=0;i50=1;
		}else{
			inum1=(i50-1)*z*pos+(iloop-1)*pos+well;
			inum2=(i50)*z*pos+(iloop-1)*pos+well;			
			tau[well]=i50+(out[inum1]-50)/(out[inum1]-out[inum2]);
		}
	}
	if(tau[well]>tauhighest) tauhighest=tau[well];
	if(tau[well]<taulowest) taulowest=tau[well];

	inum1=(nt-1)*z*pos+(iloop-1)*pos+well;
	remain[well]=out[inum1];
	if (z>1) {
		iloop=2;
		inum2=(iloop-1)*pos+well;
		recov[well]=out[inum2]-out[inum1];	}
}


setBatchMode("exit and display");

//write output
 s1="timelapse #\t"; 
//below the well series number is written into a text string
for (well=1;well<=pos;well++) {
	s1=s1+well+"\t\t";
}
s1=s1+"\n";
print(s1);
s1="time/well #\t";

//below the well position on the microtiter plate is written into a text string
j=0;i=0;
for(y=sro;y<=num_rows;y++){
	k=y-1;
	j=j+1;
	odd=j/2-round(j/2);
	for(xxx=scolumn;xxx<=num_columns;xxx++){
		x=xxx;
		if(meander==1){
			if (odd==0) x=num_columns-xxx+scolumn;
		}
		i=i+1;
		if(i<=pos) s1=s1+row_arr[k]+x+"\t\t";
	}
}
print(s1);


//below the average intensity/well and the standard deviation of this value for the cells is writen in a text string for every time point

for (iloop=1;iloop<=z;iloop++) {
	for (t=1;t<=nt;t++) {
		s2="";
		s2=s2+t+"\t";  
		for (well=1;well<=pos;well++) {
			inum=(t-1)*z*pos+(iloop-1)*pos+well;
			s2=s2+out[inum]+"\t"+out_std[inum]+"\t";			

		}
//		s2=s2+"\n";
		print(s2);
	}
}
s3="tau50%\t";
s4="initial int\t";
s5="remaining\t";

s6="recovery\t";
s7="number of cells per well\t";
for (well=1;well<=pos;well++) {
	s3=s3+tau[well]+"\t\t";	
	s4=s4+init_int[well]+"\t\t";			
	s5=s5+remain[well]+"\t\t";	
	if (z>1) s6=s6+recov[well]+"\t\t";	
	s7=s7+cellnum[well]+"\t\t";		
}
print("\n");print(s3);
print("\n");print(s4);
print("\n");print(s5);
if (z>1) {
	print("\n");print(s6);
}
print("\n");print(s7);


//==create output multiwell image

if(well96==true){
//==create50% time multiwell image	
	low=taulow;
	high=tauhigh;
	if (tau_auto==true){
		low=taulowest;
		high=tauhighest;
	}
	if(non_bl==false){
		if(int_im==false){
			newImage("multiwell", "8-bit white", 850, 500, 1);
		}else{
			newImage("multiwell", "8-bit white", 850, 950, 1);
		}
	}else{
		if(int_im==false){
			newImage("multiwell", "8-bit white", 850, 950, 1);
		}else{
			newImage("multiwell", "8-bit white", 850, 1400, 1);
		}

	}
	cs=50;
	if (num_wells==96) {
		cs=50;
		ccs=45;
	}else{
		cs=25;
		ccs=20;
	}
	i=0;j=0;
	for(y=sro;y<=num_rows;y++){
		j=j+1;
		odd=j/2-round(j/2);
		for(xxx=scolumn;xxx<=num_columns;xxx++){
			i=i+1;
			if (i<=pos){
				val=tau[i];
				val=255*(val-low)/(high-low);
				val=round(val);
				if (val<0) val=0;
				if(val>255) val=255;
				setColor(val);
				x=xxx;
				if (meander==1){
					if (odd==0) x=num_columns-xxx+scolumn;
				}
				xx=cs*x;yy=cs*y+50-cs;
				fillOval(xx, yy, ccs, ccs);
				setColor(0);
				drawOval(xx,yy,ccs,ccs);
			}	
		}
	}

   	if(num_wells==96){
		setColor(0);
		setFont("SansSerif", 32, "bold");
		for(x=1;x<=num_columns;x++) {
			xx=cs*x;
			drawString(x,xx,50);
		}
		for (k=1;k<=8; k++){
			kk=k-1;kz=100+kk*50;
			drawString(row_arr[kk],0,kz);
		}
	}else{
		setFont("SansSerif" , 16, "bold");
		setColor(0);
		for(x=1;x<=num_columns;x++) {
			xx=cs*x;
			drawString(x,xx,50);
		}
		for (k=1;k<=16; k++){
			kk=k-1;kz=75+kk*25;
			drawString(row_arr[kk],0,kz);
		}
	}
	setFont("SansSerif" , 36, "bold");	
	newImage("rampje", "8-bit ramp", 400, 50, 1);
	run("Rotate 90 Degrees Left");
	run("Copy");
	close();
	selectWindow("multiwell");
	makeRectangle(650, 50, 50, 400);
	run("Paste");
	drawRect(650, 50, 50, 400);
	drawString(low,700,450);
	drawString(high,700,100);
	drawString("T50%",700,275);
	z=475;i=0;j=0;

//==create remaining intensity after bleaching multiwell image
	if(non_bl==true){
		for(y=sro;y<=num_rows;y++){
			j=j+1;		
			odd=j/2-round(j/2);
			for(xxx=scolumn;xxx<=num_columns;xxx++){
				i=i+1;
				if(i<=pos) {
					val=remain[i];
					val=255*(val)/100; 
					val=round(val);
					if (val<0) val=0;
					if(val>255) val=255;
					setColor(val);
					x=xxx;
					if (meander==1){
						if (odd==0) x=num_columns-xxx+scolumn;
					}
					xx=cs*x;yy=cs*y+500-cs;
					iii=iii+1;
					fillOval(xx, yy, ccs, ccs);
					setColor(0);
					drawOval(xx,yy,ccs,ccs);
				}
			}
		}
	
		if(num_wells==96){
			setFont("SansSerif" , 32, "bold");
			setColor(0);
			for(x=1;x<=num_columns;x++) {
				xx=cs*x;
				drawString(x,xx,500);
			}
			for (k=1;k<=8; k++){
				kk=k-1;kz=550+kk*50;
				drawString(row_arr[kk],0,kz);
			}
		}else{
			setFont("SansSerif" , 16, "bold");
			setColor(0);
			for(x=1;x<=num_columns;x++) {
				xx=cs*x;
				drawString(x,xx,500);
			}
			for (k=1;k<=16; k++){
				kk=k-1;kz=525+kk*25;
				drawString(row_arr[kk],0,kz);
			}
		}
		setFont("SansSerif" , 36, "bold");
		makeRectangle(650, 500, 50, 400);	
		run("Paste");
		drawRect(650, 500, 50, 400);
		drawString("0%",700,900);
		drawString("100%",700,550);
		drawString("Rest",700,725);
		z=925;
	}

//==create initial intensity multiwell image
	j=0;i=0;
	if(int_im==true){
		zz=500;
		if(non_bl==true) zz=950;
		for(y=sro;y<=num_rows;y++){
			j=j+1;		
			odd=j/2-round(j/2);
			for(xxx=scolumn;xxx<=num_columns;xxx++){
				i=i+1;
				if(i<=pos) {
					val=init_int[i];
					val=255*val/itothigh; 
					val=round(val);
					if (val<0) val=0;
					if(val>255) val=255;
					setColor(val);
					x=xxx;
					if (meander==1){
						if (odd==0) x=num_columns-xxx+scolumn;
					}
					xx=cs*x;yy=cs*y+zz-cs;
					iii=iii+1;
					fillOval(xx, yy, ccs, ccs);
					setColor(0);
					drawOval(xx,yy,ccs,ccs);
				}
			}
		}
	
		if(num_wells==96){
			setFont("SansSerif" , 32, "bold");
			setColor(0);
			for(x=1;x<=num_columns;x++) {
				xx=cs*x;
				drawString(x,xx,zz);
			}
			for (k=1;k<=8; k++){
				kk=k-1;kz=zz+k*50;
				drawString(row_arr[kk],0,kz);
			}
		}else{
			setFont("SansSerif" , 16, "bold");
			setColor(0);
			for(x=1;x<=num_columns;x++) {
				xx=cs*x;
				drawString(x,xx,zz);
			}
			for (k=1;k<=16; k++){
				kk=k-1;kz=zz+k*25;
				drawString(row_arr[kk],0,kz);
			}
		}
		setFont("SansSerif" , 36, "bold");
		makeRectangle(650, zz, 50, 400);	
		run("Paste");
		zz1=zz+400;
		drawRect(650, zz, 50, 400);
		drawString("0",700,zz1);
		zz1=zz+50;
		itothigh=round(itothigh);
		drawString(itothigh,700,zz1);
		zz1=zz+225;		
		drawString("Init int",700,zz1);
		z=zz+425;
	}
//===put date and filename=================

	setFont("SansSerif" , 19, "bold");
	getDateAndTime(year,month,dw,dm,hr,mi,sec,msec);
	month=month+1;
	string="Date: "+dm+"-"+month+"-"+year;
	drawString(string,5,z);
	z=z+25;
	drawString(filein,5,z);
	run("Fire");
	print("\n");
	print(string);
	print(filein);
	print(wellplate);
	print(backgroundmode+" background\n");
	if (backgroundmode=="modal") {
		print("Number*stdev:"+thresset);
	}else{
		print("Fixed background value: "+background));
	}
	print("Low threshold for 50% time: "+taulow);
	print("High threshold for 50% time: "+tauhigh);
	print("Automatic determination of thresholds: "+tau_auto);
	print("start row: "+ srow );    
	print("Start column: "+scolumn);

}


// Pete Bosler
// February, 2013
// Animate .vtk relative vorticity plot initial latitude
// filename : vtkPlot2Panel.cpp
// Last updated : 2-16-2013
#include "vtkActor.h"
#include "vtkAxesActor.h"
#include "vtkCamera.h"
#include "vtkFollower.h"
#include "vtkPolyDataReader.h"
#include "vtkPolyData.h"
#include "vtkPolyDataMapper.h"
#include "vtkProperty.h"
#include "vtkProperty2D.h"
#include "vtkCaptionActor2D.h"
#include "vtkRenderer.h"
#include "vtkRenderWindow.h"
#include "vtkRenderWindowInteractor.h"
#include "vtkScalarBarActor.h"
#include "vtkTextActor.h"
#include "vtkTextProperty.h"
#include "vtkInteractorStyleTrackballCamera.h"
#include "vtkLookupTable.h"
#include "vtkWindowToImageFilter.h"
#include "vtkJPEGWriter.h"
#include <iostream>
#include <cmath>
#include <string.h>
#include <sstream>

using namespace std;

void GetColorForValue_BlueWhiteRed(double val, double &r, double &g, double &b, double &min, double &max);
void GetColorForValue_ColdToHot(double val, double &r, double &g, double &b, double &min, double &max);
void GetColorForValue_JetLat(double val, double &r, double &g, double &b, double &min, double &max);
void GetColorForValue_MaizeBlue(double val, double &r, double &g, double &b, double &min, double &max);
// GOALS : one panel showing direct interpolation
//		   one panel showing Lagrange interpolation

int main(int argc, const char *argv[]){
	if ( argc != 4){
		cout << "Usage : "<< argv[0] << " <jobtitle1 | jobtitle2 | frame total>\n";
		return 1;
	};
	
	char vtkFileRoot[128];
	char vtkFileRoot2[128];
	int finalFrame;
	strcpy(vtkFileRoot,argv[1]);
	strcpy(vtkFileRoot2,argv[2]);
	istringstream ss(argv[3]);
	if ( !(ss>>finalFrame) ) cerr << "Invalid final frame number.";
	
	/* CHANGE DATA PARAMETERS HERE */
	/*	TO DO : this should happen at run time */
		double dt = 0.0125;
		double tracerMin = 0.0;
		double tracerMax = 1.1;
		char scalarsDataName[16] = "TracerPanel1"; // must match .vtk file
		char scalarsDataTitle[64] = "M Tracer";
		char titleString1[36] = "Discont. Tracer Advection";
		char titleString2[56];
		char annotString1[56] = "Lagrange Interp.";
		char annotString2[56] = "Direct Interp.";
	/* END CHANGE DATA PARAMETERS */
	
	char counterString[4];
	int j;
	j = sprintf(counterString,"%04d",0);
	char vtkFileName[256];
	char vtkFileName2[256];
	strcpy(vtkFileName,vtkFileRoot);
	strcpy(vtkFileName2,vtkFileRoot2);
	strcat(vtkFileName,counterString);
	strcpy(vtkFileName2,counterString);
	strcat(vtkFileName,".vtk");
	strcat(vtkFileName2,".vtk");
	cout << "Preparing plot data ... \n";
	cout << "... reading " << finalFrame << " files beginning with : \n";
	cout << vtkFileName << "\n";
	
	// Setup VTK File Readers
	
	vtkPolyDataReader *sphereData[finalFrame+1];
	vtkPolyDataReader *sphereData2[finalFrame+1];
	for ( int frameJ = 0; frameJ<=finalFrame; frameJ++){
		
		j = sprintf(counterString,"%04d",frameJ);
		strcpy(vtkFileName,vtkFileRoot);
		strcpy(vtkFileName2,vtkFileRoot2);
		strcat(vtkFileName,counterString);
		strcat(vtkFileName2,counterString);
		strcat(vtkFileName,".vtk");
		strcat(vtkFileName2,".vtk");
		
		//initialize readers
		sphereData[frameJ]=vtkPolyDataReader::New();
		sphereData[frameJ]->SetFileName(vtkFileName);
		sphereData[frameJ]->SetScalarsName(scalarsDataName);
		sphereData2[frameJ]=vtkPolyDataReader::New();
		sphereData2[frameJ]->SetFileName(vtkFileName2);
		sphereData2[frameJ]->SetScalarsName(scalarsDataName);
	}
	cout << "... done.\n";
	
	// Set up color bar
	cout << "... Building scalar colorbar...\n";
	vtkLookupTable *tracerScale=vtkLookupTable::New();
	tracerScale->SetScaleToLinear();
	int numColors = 512;
	double range = tracerMax - tracerMin;
	tracerScale->SetRange(tracerMin,tracerMax);
	tracerScale->SetNumberOfTableValues(numColors);
	double r, g, b, val;
	for (int i=0;i<numColors;i++){
		val = tracerMin + ((double)i/numColors)*range;
		GetColorForValue_MaizeBlue(val,r,g,b,tracerMin,tracerMax);
		tracerScale->SetTableValue(i,r,g,b);
	}
	tracerScale->Build();
	cout << "... done.\n";
	
	// Setup VTK Pipeline
	vtkPolyDataMapper *sphereMapper=vtkPolyDataMapper::New();
		sphereMapper->SetScalarRange(tracerMin,tracerMax);
		sphereMapper->SetLookupTable(tracerScale);
	vtkPolyDataMapper *sphereMapper2=vtkPolyDataMapper::New();
		sphereMapper2->SetScalarRange(tracerMin,tracerMax);
		sphereMapper2->SetLookupTable(tracerScale);	
	vtkActor *sphereActor=vtkActor::New();
		sphereActor->SetMapper(sphereMapper);
	vtkActor *sphereActor2=vtkActor::New();
		sphereActor2->SetMapper(sphereMapper2);	
		//sphereActor->GetProperty()->EdgeVisibilityOn();
		//sphereActor->GetProperty()->SetEdgeColor(0.0,0.0,0.0);
	vtkScalarBarActor *colorbar = vtkScalarBarActor::New();
		colorbar->SetTitle(scalarsDataTitle);
		colorbar->GetTitleTextProperty()->SetColor(0.0,0.0,0.0);
		colorbar->SetOrientationToVertical();
		colorbar->SetPosition(0.025,0.1);
		colorbar->SetPosition2(0.9,0.9);
		colorbar->SetWidth(0.2);
		colorbar->SetLookupTable(tracerScale);
		colorbar->GetLabelTextProperty()->SetColor(0.0,0.0,0.0);
	vtkTextActor *textActor1 = vtkTextActor::New();
		textActor1->SetTextScaleModeToProp();
		textActor1->SetPosition(0.1,0.1);
		textActor1->SetPosition2(0.8,0.3);
		textActor1->GetTextProperty()->SetColor(0.0,0.0,0.0);
	vtkTextActor *lagrangeLabel = vtkTextActor::New();
		//lagrangeLabel->GetPositionCoordinate()->SetCoordinateSystemToNormalizedDisplay();
		lagrangeLabel->SetDisplayPosition(200,550);
		lagrangeLabel->SetTextScaleModeToNone();
		//lagrangeLabel->SetPosition(0.25,0.8);
		//lagrangeLabel->SetPosition2(0.8,0.3);
		lagrangeLabel->GetTextProperty()->SetColor(0.0,0.0,0.0);
		lagrangeLabel->GetTextProperty()->SetFontSize(42);
		lagrangeLabel->SetInput(annotString1);
	vtkTextActor *directLabel = vtkTextActor::New();
		//directLabel->GetPositionCoordinate()->SetCoordinateSystemToNormalizedDisplay();
		directLabel->SetDisplayPosition(800,550);
		directLabel->SetTextScaleModeToNone();
		//directLabel->SetPosition(0.65,0.8);
		//directLabel->SetPosition2(0.8,0.3);
		directLabel->GetTextProperty()->SetColor(0.0,0.0,0.0);
		directLabel->GetTextProperty()->SetFontSize(42);
		directLabel->SetInput(annotString2);
	vtkCamera *camera = vtkCamera::New();
		camera->SetPosition(5.0,0.0,1.0);
		camera->SetFocalPoint(0.0,0.0,0.0);
		camera->SetViewUp(0.0,0.0,1.0);
	vtkRenderer *renderer = vtkRenderer::New();
		renderer->AddActor(sphereActor);
		renderer->AddActor(textActor1);
		renderer->AddActor(lagrangeLabel);
		renderer->AddActor(colorbar);
		renderer->SetActiveCamera(camera);
		renderer->SetBackground(0.9,0.9,0.9);
		renderer->SetViewport(0.0,0.0,0.5,1.0);
	vtkRenderer *renderer2 = vtkRenderer::New();
		renderer2->AddActor(sphereActor2);
		renderer2->AddActor(directLabel);
		//renderer->AddActor(textActor1);
		//renderer->AddActor(colorbar);
		renderer2->SetActiveCamera(camera);
		renderer2->SetBackground(0.9,0.9,0.9);
		renderer2->SetViewport(0.5,0.0,1.0,1.0);
	vtkRenderWindow *renWin = vtkRenderWindow::New();
		renWin->AddRenderer(renderer);
		renWin->AddRenderer(renderer2);
		renWin->SetSize(1200,600);
	vtkWindowToImageFilter *win2im = vtkWindowToImageFilter::New();
		win2im->SetInput(renWin);
	vtkJPEGWriter *writer=vtkJPEGWriter::New();
		char jpgFileRoot[128];
		char jpgFileName[128];
		strcpy(jpgFileRoot,"jpgOut/tracerFrame_");
	cout << "... done.\n";
	
	// RENDERING LOOP
	cout << "... RENDERING ... \n";
	int nActive = 0;
	for ( int frameJ =0; frameJ<=finalFrame; frameJ++){
		
		sphereMapper->SetInput(sphereData[frameJ]->GetOutput());
		sphereMapper2->SetInput(sphereData2[frameJ]->GetOutput());
		
		j=sprintf(titleString2,"t = %7.4f, N = %6d",frameJ*dt,nActive);
		textActor1->SetInput(titleString2);
		
		j=sprintf(counterString,"%04d",frameJ);
		strcpy(jpgFileName,jpgFileRoot);
		strcat(jpgFileName,counterString);
		strcat(jpgFileName,".jpg");
		
		renWin->Render();
		
		win2im->Modified();
		
		writer->SetInput(win2im->GetOutput());
		writer->SetFileName(jpgFileName);
		writer->Write();
		
		nActive = sphereData[frameJ]->GetOutput()->GetNumberOfCells();
		
		if ( frameJ == finalFrame/4){cout << "... 25\% done.\n";}
		if ( frameJ == finalFrame/2){cout << "... 50\% done.\n";}
		if ( frameJ == 3*finalFrame/4){cout << "... 75\% done.\n";}
	}
	// Plot last frame
	sphereMapper->SetInput(sphereData[finalFrame]->GetOutput());
	sphereMapper2->SetInput(sphereData2[finalFrame]->GetOutput());
	j=sprintf(counterString,"%04d",finalFrame+1);
	strcpy(jpgFileName,jpgFileRoot);
	strcat(jpgFileName,counterString);
	strcat(jpgFileName,".jpg");
	renWin->Render();
	win2im->Modified();
	writer->SetInput(win2im->GetOutput());
	writer->SetFileName(jpgFileName);
	writer->Write();
	
	// Clean up
	writer->Delete();
	win2im->Delete();
	renWin->Delete();
	renderer->Delete();
	renderer2->Delete();
	camera->Delete();
	sphereActor->Delete();
	sphereActor2->Delete();
	textActor1->Delete();
	colorbar->Delete();
	tracerScale->Delete();
	sphereMapper->Delete();
	sphereMapper2->Delete();
	for (int frameJ=0; frameJ<=finalFrame; frameJ++){
		sphereData[frameJ]->Delete();
		sphereData2[frameJ]->Delete();
	}
};

void GetColorForValue_BlueWhiteRed(double val, double &r, double &g, double &b, double &min,double &max)
{
	const int numColors = 3;
	const double range = max - min;
	const double colors[numColors][3] =  { 0.0, 0.0, 1.0, //blue
							1.0, 1.0, 1.0, //white
							1.0, 0.0, 0.0 };//red
	if ( val <= min )
	{
		r = colors[0][0];
		g = colors[0][1];
		b = colors[0][2];
	}
	else if ( val > max)
	{
		r = colors[numColors-1][0];
		g = colors[numColors-1][1];
		b = colors[numColors-1][2];
	}
	else
	{							
		for (int j=0;j<numColors;j++)
		{
			double floorj = min + ((double)j/(numColors-1))*range;
			double ceilj = min + ((double)(j+1)/(numColors-1))*range;
			if ( (val > floorj) && (val <= ceilj) ){
				double frac = ( val - floorj)/(ceilj-floorj);
				r = colors[j][0]*(1.0-frac) + colors[j+1][0]*frac;
				g = colors[j][1]*(1.0-frac) + colors[j+1][1]*frac;
				b = colors[j][2]*(1.0-frac) + colors[j+1][2]*frac;
			}
		}
	}
};

void GetColorForValue_MaizeBlue(double val, double &r, double &g, double &b, double &min,double &max)
{
	const int numColors = 3;
	const double range = max - min;
	const double colors[numColors][3] = { 0.0, 0.0, 0.4, // midnight blue
										  1.0, 1.0, 1.0, // white
										  1.0, 0.8, 0.2}; // yellow
	if ( val <= min )
	{
		r = colors[0][0];
		g = colors[0][1];
		b = colors[0][2];
	}
	else if ( val > max)
	{
		r = colors[numColors-1][0];
		g = colors[numColors-1][1];
		b = colors[numColors-1][2];
	}
	else
	{							
		for (int j=0;j<numColors;j++)
		{
			double floorj = min + ((double)j/(numColors-1))*range;
			double ceilj = min + ((double)(j+1)/(numColors-1))*range;
			if ( (val > floorj) && (val <= ceilj) ){
				double frac = ( val - floorj)/(ceilj-floorj);
				r = colors[j][0]*(1.0-frac) + colors[j+1][0]*frac;
				g = colors[j][1]*(1.0-frac) + colors[j+1][1]*frac;
				b = colors[j][2]*(1.0-frac) + colors[j+1][2]*frac;
			}
		}
	}
};									  

void GetColorForValue_JetLat(double val, double &r, double &g, double &b, double &min, double &max)
{
	const int numColors = 9;
	const double range = max-min;
	const double colors[numColors][3] = {0.0, 1.0, 1.0, //cyan
										 0.0, 0.0, 1.0,//blue
						  				 0.8549, 0.4392157, 0.839216,//orchid
						   				 0.51765, 0.4392157, 1.0,//light slate blue
						   				 0.28235, 0.8196078, 0.8,//medium turqoise
										 0.0, 1.0, 0.0,//green
						   				 1.0, 0.843137, 0.0,//gold
						   				 1.0, 0.54902, 0.0,//dark orange
						   				 1.0, 1.0, 0.0};//yellow
	double frac;
	double floor;
	double ceil;
	double points[9] = {-1.5708, -0.7854, 0.0, 0.6, 0.7, 0.7854, 0.9, 1.0, 1.5708};
	int color0;
	
	double c1, c2, c3;
	double p1, p2, p3;
	int color1, color2, color3;
	for (int j=0; j < numColors-1; j++)
	{
		if (( val > points[j]) && ( val<=points[j+1]))
		{
			floor = points[j];
			ceil = points[j+1];
			color0 = j;
		}
	}

	/* Linear color weighting */
	if ( val <= points[0])
		{
			r = colors[0][0];
		 	g = colors[0][1];
		 	b = colors[0][2];
		 }
	else if ( val > points[numColors-1])
		{
		   r = colors[numColors-1][0];
		   g = colors[numColors-1][1];
		   b = colors[numColors-1][2];
		}
	else
		{
		frac = (val-floor)/(ceil-floor);
		r = colors[color0][0]*(1.0-frac) + colors[color0+1][0]*frac;
		g = colors[color0][1]*(1.0-frac) + colors[color0+1][1]*frac;
		b = colors[color0][2]*(1.0-frac) + colors[color0+1][2]*frac;
		}

};

void GetColorForValue_ColdToHot(double val, double &r, double &g, double &b, double &min, double &max)
{
	const int numColors = 7;
	const double range = max - min;
	const double colors[numColors][3] = { 0.87843, 1.0, 1.0, //light cyan
							0.0, 1.0, 1.0, // cyan
							0.0, 0.0, 1.0, // blue
							0.0, 0.0, 0.0, // black
							1.0, 0.0, 0.0, // red
							1.0, 1.0, 0.0, // yellow
							1.0, 1.0, 0.87843}; // light yellow
	for (int j=0;j<numColors;j++){
		double floorj = min + ((double)j/(numColors-1))*range;
		double ceilj = min +((double)(j+1)/(numColors-1))*range;
		if ( (val > floorj) && (val <= ceilj) ) {
			double frac = ( val-floorj)/(ceilj-floorj);
			r = colors[j][0]*(1.0-frac) + colors[j+1][0]*frac;
			g = colors[j][1]*(1.0-frac) + colors[j+1][1]*frac;
			b = colors[j][2]*(1.0-frac) + colors[j+1][2]*frac;
		}
	}							

};


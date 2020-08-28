% This script is made to test Bangga's model on SH2019
% Author : Lucas Schneeberger
% Date : 11.06.2020

close all
clear all
clc 
set(0,'DefaultFigureWindowStyle','docked')
addpath('../plot_dir/')
addpath('../src/model/')
addpath('../src/common/')
addpath('../src/lib/')
run('/Users/lucas/src/codes_smarth/labbook.m')

%% Define the airfoil and the associated steady curve

airfoil = Airfoil('flatplate',0.15);
airfoil.r0 = 0.04;
static = load(fullfile('..','static_flatplate'));
airfoil.steady = SteadyCurve(static.alpha,static.CN,13);

%% Set up the ramp

c = 2;

data = load(loadmat(LB(c).ms,LB(c).mpt),'raw','inert','avg','zero');
raw = data.raw;
inert = data.inert;
inert.alpha = raw.alpha(raw.t>=0);
msname = sprintf('ms%03impt%i',LB(c).ms,LB(c).mpt);
ramp = RampUpMotion('alpha',inert.alpha,'t',inert.t,'V',LB(c).U,'alphadot',LB(c).alphadot);
ramp_filt = RampUpMotion('alpha',inert.alpha,'t',inert.t,'V',LB(c).U,'alphadot',LB(c).alphadot);
evalin('base',sprintf('ramp.setName(''%s'') ',msname))
evalin('base',sprintf('ramp_filt.setName(''%s'')',msname))

Cl = inert.Cl;
Cd = inert.Cd;
fs = 1/ramp.Ts;
Clf = myFilterTwice(Cl,fs);
Cdf = myFilterTwice(Cd,fs);
ramp.setCL(Clf);
ramp.setCD(Cdf);

ramp.computeAirfoilFrame();
ramp.isolateRamp();
ramp.setPitchRate(airfoil);
% Define stall (convectime must have been set)
ramp.findExpOnset();
%% Run Leishman-Beddoes' model on the ramp

ramp.BeddoesLeishman(airfoil,3,1,2,1.8,'experimental')
ramp.plotFatma()
% saveas(gcf,'../fig/CNv_limcrit','png')
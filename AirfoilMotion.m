classdef AirfoilMotion < matlab.mixin.SetGet
    properties
        name
        % experimental pitch angle evolutions
        alpha
        alpha_rad
        analpha
        analpha_rad
        alphadot_rad
        % exprimental load curves
        CL
        CD
        CN
        CC
        % experimental parts
        Ts
        t
        S % convective time
        rt % instantaneous red. pitch rate
        % experimental flow parameters
        V
        M
        %% Beddoes-Leishman
        DeltaS
        Tp
        Tf
        Tv
        % Attached flow behaviour
        CNI
        CNC
        CCC
        CNp
        alphaE
        alphaE_rad
        % LE separation
        CNprime
        % TE separation
        alphaf
        alphaf_rad
        CNk
        f
        fp
        fpp
        CNf
        CCf
        % Dynamic Stall
        CNv
        CN_LB
        %% Goman-Khrabrov
        tau1
        tau2
        x
        alpha_shift
        CN_GK
        %% Sheng 
        alpha_lag
        analpha_lag
    end
    properties (Constant = true)
        % Beddoes constants
        A1 = 0.3;
        A2 = 0.7;
        b1 = 0.14;
        b2 = 0.53;
        % speed of sound
        a = 340.3;
    end
    methods
        function obj = AirfoilMotion(varargin)
            % convenient constructor with name/value pair of any attribute of
            % AirfoilMotion
            p = inputParser;
            % Add name / default value pairs
            mco = ?AirfoilMotion;
            prop = mco.PropertyList; % makes a cell array of all properties of the specified ClassName; % makes a cell array of all properties of the specified ClassName
            for k=1:length(prop)
                if ~prop(k).Constant
                    p.addParameter(prop(k).Name,[]);
                end
            end
            p.parse(varargin{:}); % {:} is added to take the content of the cells
            % Add name / default value pairs
            for k=1:length(prop)
                if ~prop(k).Constant
                    obj.set(prop(k).Name,p.Results.(prop(k).Name))
                end
            end
        end
        function fillProps(obj)
            % fills the properties that can be deduced from one another
            if ~isempty(obj.alpha)
                obj.alpha_rad = deg2rad(obj.alpha);
            end
            if ~isempty(obj.Ts) && isempty(obj.t)
                obj.t = 0:obj.Ts:obj.Ts*(length(obj.alpha)-1);
            end
            if isempty(obj.Ts) && ~isempty(obj.t)
                obj.Ts = mean(diff(obj.t));
            end
            if ~isempty(obj.V) && isempty(obj.M)
                obj.M = obj.V/obj.a;
            end
            if isempty(obj.V) && ~isempty(obj.M)
                obj.V = obj.M*obj.a;
            end
        end
        function setName(obj,name)
            if nargin > 1
                obj.name = name;
            else
                obj.name = inputname(1);
            end
        end
        function beta = beta(obj)
            if obj.M < 1
                beta = sqrt(1-obj.M^2);
            else
                beta = sqrt(obj.M^2-1);
            end
        end
        function computeAirfoilFrame(obj)
            if ~isempty(obj.CD) && ~isempty(obj.CL)
                if ~isempty(obj.CC) || ~isempty(obj.CN)
                    warning('The data for CN and CC will be erased.')
                end
                obj.CN = obj.CL.*cos(obj.alpha_rad) + obj.CD.*sin(obj.alpha_rad);
                obj.CC = obj.CD.*cos(obj.alpha_rad) - obj.CL.*sin(obj.alpha_rad);
            else
                error('CL and CD must be defined to compute CN and CC.')
            end
        end
        function computeFlowFrame(obj)
            if ~isempty(obj.CC) && ~isempty(obj.CN)
                if ~isempty(obj.CD) || ~isempty(obj.CL)
                    warning('The data for CL and CD will be erased.')
                end
                obj.CL = obj.CN.*cos(obj.alpha_rad) - obj.CC.*sin(obj.alpha_rad);
                obj.CD = obj.CC.*cos(obj.alpha_rad) + obj.CN.*sin(obj.alpha_rad);
            else
                error('CL and CD must be defined to compute CN and CC.')
            end
        end
        function BeddoesLeishman(obj,airfoil,Tp,Tf,Tv,alphamode)
            airfoil.steady.fitKirchhoff()
            obj.computeAttachedFlow(airfoil,alphamode);
            obj.computeLEseparation(airfoil,Tp,alphamode);
            obj.computeTEseparation(airfoil,Tf);
            obj.computeDS(Tv);
        end
        function computeAttachedFlow(obj,airfoil,alphamode)
            obj.S = 2*obj.V*obj.t/airfoil.c;
            obj.DeltaS = mean(diff(obj.S));
            obj.computeImpulsiveLift(airfoil,alphamode);
            obj.computeCirculatoryLift(airfoil,alphamode);
            % effective angle of attack
            obj.alphaE = obj.CNC/airfoil.steady.slope; % slope is in deg
            obj.alphaE_rad = deg2rad(obj.alphaE);
            % chord force
            obj.CCC = obj.CNC.*tan(obj.alphaE_rad);
            % Potential normal coefficient
            if length(obj.CNI)<length(obj.CNC)
                obj.CNp = obj.CNI + obj.CNC(1:length(obj.CNI));
            else
                obj.CNp = obj.CNI(1:length(obj.CNC))+obj.CNC;
            end
        end
        function computeImpulsiveLift(obj,airfoil,alphamode)
            % Impulsive (non-circulatory) normal coeff
            Kalpha = 0.75/(1-obj.M+pi*obj.beta*obj.M^2*(obj.A1*obj.b1+obj.A2*obj.b2)); % time constant
            Tl = airfoil.c/obj.a;
            Talpha = Kalpha*Tl;
            switch(alphamode)
                case 'experimental'
                    obj.computeExperimentalImpulsiveLift(Talpha)
                case 'analytical'
                    obj.computeAnalyticalImpulsiveLift(Talpha)
            end
        end
        function computeExperimentalImpulsiveLift(obj,Talpha)
            % experimental alphas, angles in rad
            dalpha = diff(obj.alpha_rad); % should be degrees, but only radians work!
            ddalpha = diff(dalpha); % same unit as above
            D = zeros(size(ddalpha));
            for n=2:length(ddalpha)
                D(n) = D(n-1)*exp(-obj.Ts/Talpha)+(ddalpha(n)/obj.Ts)*exp(-obj.Ts/(2*Talpha));
            end
            dalphadt = (dalpha(2:end) + dalpha(1:end-1))/(2*obj.Ts); % way smoother than Euler method (dalphadt = dalpha(1:end-1)/obj.Ts)!            
            obj.CNI = 4*Talpha/obj.M*(dalphadt-D);
        end
        function computeCirculatoryLift(obj,airfoil,alphamode)
            % Circulatory normal coeff
            switch alphamode
                case 'experimental'
                    obj.computeExperimentalCirculatoryLift(airfoil);
                case 'analytical'
                    obj.computeAnalyticalCirculatoryLift(airfoil);
                otherwise
                    error('The type of alpha to be taken for computations has to be specified.')
            end
        end        
        function computeExperimentalCirculatoryLift(obj,airfoil)
            deltaalpha = diff(obj.alpha_rad); % should be in degrees, but only radians work
            rule = 'mid-point';
            [X,Y] = obj.computeDuhamel(deltaalpha,rule);
            obj.CNC = airfoil.steady.slope*(reshape(obj.alpha(1:length(X)),size(X))-X-Y); % alpha is in degrees, slope is in 1/deg
        end
        function [X,Y] = computeDuhamel(obj,deltaalpha,rule)
            % Choose the best-suited algorithm for approximation of the
            % Duhamel integral. Rectangle is not recommended is the
            % step size in convective time is small, but can be 10
            % times faster to execute. Useful for numerous datapoints. (See section
            % 8.14.1 of Principles of Helicopter Aerodynamics by J.
            % Gordon Leishman)
            X = zeros(size(deltaalpha));
            Y = zeros(size(deltaalpha));
            switch rule
                case 'mid-point'  % approximation of Duhamel's integral using mid-point rule.
                    % Error of order DeltaS^3 (< 1% if both b1*DeltaS and b2*DeltaS are <0.25)
                    for n=2:length(deltaalpha)
                        X(n) = X(n-1)*exp(-obj.b1*obj.beta^2*obj.DeltaS) + obj.A1*deltaalpha(n)*exp(-obj.b1*obj.beta^2*obj.DeltaS/2);
                        Y(n) = Y(n-1)*exp(-obj.b2*obj.beta^2*obj.DeltaS) + obj.A2*deltaalpha(n)*exp(-obj.b2*obj.beta^2*obj.DeltaS/2);
                    end
                case 'rectangle' % approximation of the integral using rectangle rule.
                    % Faster, but error of order DeltaS (< 5% if both b1*DeltaS and b2*DeltaS are <0.05)
                    for n=2:length(deltaalpha)
                        X(n) = X(n-1)*exp(-obj.b1*obj.beta^2*obj.DeltaS) + obj.A1*deltaalpha(n);
                        Y(n) = Y(n-1)*exp(-obj.b2*obj.beta^2*obj.DeltaS) + obj.A2*deltaalpha(n);
                    end
            end
            
        end
        function computeLEseparation(obj,airfoil,Tp,alphamode)
            % Computes the delayed normal coefficient, CNprime, depending
            % on the time constant Tp for a given airfoil undergoing the
            % instanciated pitching motion.
            obj.Tp = Tp;
            Dp = zeros(size(obj.CNp));
            for n=2:length(obj.CNp)
                Dp(n) =  Dp(n-1)*exp(-obj.DeltaS/obj.Tp) + (obj.CNp(n)-obj.CNp(n-1))*exp(-obj.DeltaS/(2*obj.Tp));
            end
            switch alphamode
                case 'analytical'
                    obj.CNprime = airfoil.steady.slope*obj.analpha(1:length(Dp)) - Dp; % we pretend the flow is attached over the whole alpha-range
                case 'experimental'
                    obj.CNprime = airfoil.steady.slope*obj.alpha(1:length(Dp)) - Dp; % we pretend the flow is attached over the whole alpha-range
            end 
        end
        function computeTEseparation(obj,airfoil,Tf)
            obj.Tf = Tf;
            obj.f = seppoint(airfoil.steady,airfoil.steady.alpha);
            
            % Kirchhoff law
            obj.CNk = Kirchhoff(airfoil.steady,airfoil.steady.alpha);
            
            obj.alphaf = obj.CNprime/airfoil.steady.slope;
            obj.alphaf_rad = deg2rad(obj.alphaf);
            
            obj.fp = seppoint(airfoil.steady,obj.alphaf); % effective separation point
            
            Df=zeros(size(obj.fp));
            for n=2:length(obj.fp)
                Df(n) = Df(n-1)*exp(-obj.DeltaS/Tf) + (obj.fp(n)-obj.fp(n-1))*exp(-obj.DeltaS/(2*Tf));
            end
            
            obj.fpp = obj.fp - Df;
            
            if length(obj.CNI)<length(obj.CNC)
                obj.CNf = ((1+sqrt(obj.fpp))/2).^2.*obj.CNC(1:length(obj.CNI))+obj.CNI;
            else
                obj.CNf = ((1+sqrt(obj.fpp))/2).^2.*obj.CNC+obj.CNI(1:length(obj.CNC));
            end
            
            eta = 0.95;
            obj.CCf = eta*airfoil.steady.slope*obj.alphaE(1:length(obj.fpp)).^2.*sqrt(obj.fpp);
        end
        function computeDS(obj,Tv)
            % Computes the final Beddoes-Leishman predicted CN for the instanciated pitching motion, after
            % having computed the attached-flow behavior and both TE and LE
            % separation with the homolog methods.
            obj.Tv = Tv;
            
            % vortex normal coeff
            KN = (1+sqrt(obj.fpp)).^2/4;
            Cv = obj.CNC(1:length(KN)).*(1-KN);
            
            obj.CNv=zeros(size(Cv));
            for n=2:length(Cv)
                obj.CNv(n) = obj.CNv(n-1)*exp(-obj.DeltaS/Tv) + (Cv(n)-Cv(n-1))*exp(-obj.DeltaS/(2*Tv));
            end
            
            % normal force coefficient
            obj.CN_LB = obj.CNf + obj.CNv;
        end
        function GomanKhrabrov(obj,steady,tau1,tau2)
            % Resample CNsteady to fit experimental unsteady alphas
            obj.tau1 = tau1;
            obj.tau2 = tau2;
            steady.setCN0();
            obj.setCNsteady(steady)
            steady.computeSlope();
            steady.computeSeparation();
            obj.alphadot_rad = diff(obj.alpha_rad)./diff(obj.t);
            obj.alpha_shift = obj.alpha_rad(1:length(obj.alphadot_rad))-tau2*obj.alphadot_rad;
            u = obj.alpha_shift;
            u(u<min(steady.alpha_rad)) = min(steady.alpha_rad);
            u(u>max(steady.alpha_rad)) = max(steady.alpha_rad);
            x0 = interp1(steady.alpha_rad,steady.fexp,u);
            sys = ss(-1/tau1,1/tau1,1,0);
            obj.x = lsim(sys,x0,obj.t(1:length(x0)));
            obj.CN_GK = steady.slope/4*(1+sqrt(obj.x)).^2+steady.CN0;
        end
        function computeAlphaLag(obj,airfoil)
            % computes the delayed angle of attack alpha_lag w.r.t. the
            % experimental angle of attack alpha. The time constant for the
            % delay is the corresponding Talpha(r), r being the reduced
            % pitch rate of the ramp-up motion.
            obj.S = obj.t*obj.V/(airfoil.c/2);
            Talpha = interp1(airfoil.r,airfoil.Talpha,obj.r);
            obj.DeltaS = mean(diff(obj.S));
            if ~isempty(obj.alpha) % compute alpha_lag from alpha using Eq.5
                dalpha = diff(obj.alpha);
                obj.alpha_lag = zeros(size(obj.alpha));
                Dalpha = zeros(size(obj.alpha));
                for k = 1:length(dalpha)
                    Dalpha(k+1) = Dalpha(k)*exp(-obj.DeltaS/Talpha) + dalpha(k)*exp(-obj.DeltaS/(2*Talpha));
                end
                obj.alpha_lag = obj.alpha - Dalpha;
                % compute analpha_lag from alpha_lag
                dalpha_lagdt = diff(obj.alpha_lag)./diff(obj.t);
                alphadot_lag = max(dalpha_lagdt);
                analpha_lag0 = lsqcurvefit(@(x,xdata) alphadot_lag*xdata+x,0,obj.t(dalpha_lagdt>=5),obj.alpha_lag(dalpha_lagdt>=5));
                obj.analpha_lag =  alphadot_lag*obj.t + analpha_lag0;
                
            elseif ~isempty(obj.analpha) % compute analpha_lag from analpha
                dalpha = diff(obj.analpha);
                obj.analpha_lag = zeros(size(obj.analpha));
                Dalpha = zeros(size(obj.alpha));
                for k = 1:length(dalpha)
                    Dalpha(k+1) = Dalpha(k)*exp(-obj.DeltaS/Talpha) + dalpha(k)*exp(-obj.DeltaS/(2*Talpha));
                end
                obj.alpha_lag = obj.alpha - Dalpha;
            end
        end
        function plotAlpha(obj)
            figure
            if ~isempty(obj.alpha)
                plot(obj.t,obj.alpha,'DisplayName','exp')
                hold on
            end
            if ~isempty(obj.analpha)
                plot(obj.t,obj.analpha,'--','DisplayName','ideal')
                hold on
            end
            legend show
            grid on
            xlabel('t (s)')
            ylabel('\alpha (°)')
            title(obj.name)
        end
        function plotPolars(obj)
            figure
            suptitle(sprintf('Polar plots %s',obj.name))
            subplot(221)
            plot(obj.alpha,obj.CL)
            xlabel('\alpha (°)')
            ylabel('C_L')
            grid on
            subplot(222)
            plot(obj.alpha,obj.CD)
            xlabel('\alpha (°)')
            ylabel('C_D')
            grid on
            subplot(223)
            plot(obj.alpha,obj.CN)
            xlabel('\alpha (°)')
            ylabel('C_N')
            grid on
            subplot(224)
            if ~isempty(obj.CC)
                plot(obj.alpha,obj.CC)
                xlabel('\alpha (°)')
                ylabel('C_C')
                grid on
            end
        end        
        function plotGK(obj)
            figure
            plot(obj.alpha(1:length(obj.CN_GK)),obj.CN_GK,'LineWidth',2)
            xlabel('\alpha (°)')
            ylabel('C_N')
            grid on
            title(sprintf('\\tau_1 = %.3f \\tau_2 = %.2f',obj.tau1,obj.tau2))
        end
        function plotAlphas(obj)
            figure
            plot(obj.t,obj.alpha,'LineWidth',2,'DisplayName','\alpha_{xp}')
            hold on
            plot(obj.t(1:length(obj.alphaf)),obj.alphaf,'DisplayName','\alpha_f')
            plot(obj.t(1:length(obj.alphaE)),obj.alphaE,'DisplayName','\alpha_E')
            grid on
            legend('Location','Best')
            xlabel('time (s)')
            ylabel('\alpha (°)')
        end
        function plotSeparation(obj,airfoil,mode,save)
            figure
            switch mode
                case 'normal'
                    plot(airfoil.steady.alpha,obj.f,'DisplayName','f')
                    hold on
                    plot(obj.alpha(1:length(obj.fp)),obj.fp,'DisplayName','f''')
                    plot(obj.alpha(1:length(obj.fpp)),obj.fpp,'DisplayName','f''''')
                case 'log'
                    semilogy(airfoil.steady.alpha,airfoil.steady.fexp,'DisplayName','experimental')
                    hold on
                    semilogy(airfoil.steady.alpha,obj.f,'DisplayName','model')
            end
            legend show
            title(sprintf('%s (Tp = %.2f, Tf = %.2f, Tv = %.2f)',obj.name,obj.Tp,obj.Tf,obj.Tv))
            grid on
            xlabel('\alpha (°)')
            ylabel('separation point (x/c)')
            if save
                saveas(gcf,'fig/f_curves.png')
            end
        end
        function plotSheng(obj,airfoil)
            figure
            plot(obj.rss,obj.alpha_ds,'.','DisplayName','\alpha_{ds} (exp)','MarkerSize',20)
            hold on 
            plot(airfoil.r,airfoil.alpha_ds)
            grid on
            ylabel('\alpha_{ds} (°)','FontSize',20);
            ax = gca;
            ax.FontSize = 20;
        end
        function plotAlphaLag(obj,airfoil)
            figure
            if ~isempty(obj.alpha)
                plot(obj.t,obj.alpha,'DisplayName','\alpha')
                hold on
                plot(obj.t,obj.alpha_lag,'DisplayName','\alpha''')
            end
            if ~isempty(obj.analpha)
                plot(obj.t,obj.analpha,'--','DisplayName','ideal \alpha')
                hold on
                %plot(obj.t,obj.analpha_lag,'--','DisplayName','ideal \alpha''')
            end
            if ~isempty(obj.i_CConset)
                plot(obj.t(obj.i_CConset),obj.alpha_CConset,'rx','DisplayName','\alpha_{ds,CC}')
                hold on
                %plot(obj.t(obj.i_CConset),obj.alpha_lag(obj.i_CConset),'bx','DisplayName','\alpha''_{ds,CC}')
            end
            plot(obj.t(obj.i_CConset),airfoil.steady.alpha_static_stall,'x','DisplayName','\alpha_{ss}')
            [Talpha,t0] = airfoil.findTalpha(obj);
            plot(obj.t,obj.alphadot*(obj.t-t0-Talpha*(1-exp(-(obj.t-t0)/Talpha))),'--','DisplayName','ideal ramp response')
            grid on
            xlabel('t (s)')
            ylabel('\alpha')
            title(sprintf('%s ($\\dot{\\alpha} = %.2f ^{\\circ}$/s)',obj.name,obj.alphadot),'interpreter','latex')
            legend('Location','SouthEast')
        end
    end
end

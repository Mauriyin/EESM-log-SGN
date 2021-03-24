function out = box0Simulation1IntUser1(simParams)
% box0Simulation Example helper function

%   Copyright 2019 The MathWorks, Inc.

% Extract configuration
cfgHE = simParams.Config;
cfgHEInt = simParams.Config;
substreamidx = simParams.RandomSubstream;
maxNumPackets = simParams.MaxNumPackets;
maxNumErrors = simParams.MaxNumErrors;
numUsers = size(cfgHE.User,2);
snr = simParams.SNR;
% Generate per-user channels for BSS 1: tgaxChannel
tgaxChannel = cell(1,numUsers);
for userIdx = 1:numUsers
    tgaxChannel{userIdx} = clone(simParams.Channel);
    tgaxChannel{userIdx}.UserIndex = userIdx; % Set unique user index
end
% Generate per-user channels for BSS 2: tgaxChannel2
tgaxChannel2 = cell(1,numUsers);
for userIdx = 1:numUsers
    tgaxChannel2{userIdx} = clone(simParams.Channel);
    tgaxChannel2{userIdx}.UserIndex = userIdx; % Set unique user index
end
% Set up interference channel: tgaxChannelInterference
tgaxChannelInterference = clone(simParams.Channel);

% Create an NDP packet for BSS 1
cfgNDP = wlanHESUConfig('APEPLength',0,'GuardInterval',0.8); % No data in an NDP
cfgNDP.ChannelBandwidth = cfgHE.ChannelBandwidth;
cfgNDP.NumTransmitAntennas = cfgHE.NumTransmitAntennas;
cfgNDP.NumSpaceTimeStreams = cfgHE.NumTransmitAntennas;

% Create an NDP packet for BSS 2 
cfgNDPInt = wlanHESUConfig('APEPLength',0,'GuardInterval',0.8); % No data in an NDP
cfgNDPInt.ChannelBandwidth = cfgHEInt.ChannelBandwidth;
cfgNDPInt.NumTransmitAntennas = cfgHEInt.NumTransmitAntennas;
cfgNDPInt.NumSpaceTimeStreams = cfgHEInt.NumTransmitAntennas;

% Set random substream index per iteration to ensure that each
% iteration uses a repeatable set of random numbers
stream = RandStream('combRecursive','Seed',99);
stream.Substream = substreamidx;
RandStream.setGlobalStream(stream);

% Indices to extract fields from the PPDU
ind = wlanFieldIndices(cfgHE);
indInt = wlanFieldIndices(cfgHEInt);

% Per user processing, focus on the first user
userIdx = 1;
Nsts = cfgHE.User{userIdx}.NumSpaceTimeStreams;
% Get occupied subcarrier indices and OFDM parameters
ruIdx = 1;
ofdmInfo = wlanHEOFDMInfo('HE-Data',cfgHE,ruIdx);

% Create an instance of the AWGN channel per SNR point simulated
awgnChannel = comm.AWGNChannel;
awgnChannel.NoiseMethod = 'Signal to noise ratio (SNR)';
% Account for noise energy in nulls so the SNR is defined per
% active subcarrier
awgnChannel.SNR = snr-10*log10(ofdmInfo.FFTLength/sum(ruInfo(cfgHE).RUSizes));
N0 = 10^(-awgnChannel.SNR/10);  

% Get path filers for last channel (same for all channels)
chanInfo = info(tgaxChannel{userIdx});
pathFilters = chanInfo.ChannelFilterCoefficients; 
interferenceChanInfo = info(tgaxChannelInterference);
interferencePathFilter = interferenceChanInfo.ChannelFilterCoefficients;

% Create object to deal with abstraction
Abstraction = tgaxLinkPerformanceModel;

% Loop to simulate multiple packets
perStore = nan(maxNumPackets,1);
perAbsStore = nan(maxNumPackets,1);
perAbsRawStore = nan(maxNumPackets,1);
snreffStore = nan(maxNumPackets,1);
sinrStore = nan(ruInfo(cfgHE).RUSizes(userIdx),cfgHE.User{userIdx}.NumSpaceTimeStreams,maxNumPackets); % Nsc-by-Nsts-by-maxNumPackets
numPacketErrors = 0;
numPacketErrorsAbs = 0;
numPkt = 1; % Index of packet transmitted
while numPacketErrors<=maxNumErrors && numPkt<=maxNumPackets
    % Pass through a fading indoor TGax channel
    for userIdx = 1:numel(tgaxChannel)
        reset(tgaxChannel{userIdx}); % Reset channel for different realization
        reset(tgaxChannel2{userIdx}); % Reset channel for different realization
    end
    reset(tgaxChannelInterference); 
    
    % -------------------------------------------------------------------
    % Comment this to run simulation without beamforming
    % Generate NDP packet in BSS 1 - with an empty PSDU as no data
    txNDP = wlanWaveformGenerator([],cfgNDP);
    % For each user STA, pass the NDP packet through the channel and calculate
    % the feedback channel state matrix by SVD.
    staFeedback = cell(1,numUsers);
    for userIdx = 1:numel(tgaxChannel)
        % Received waveform at user STA with 50 sample padding. No noise.
        rxNDP = tgaxChannel{userIdx}([txNDP; zeros(50,size(txNDP,2))]);
        
        % Get the full-band beamforming feedback for a user
        staFeedback{userIdx} = heUserBeamformingFeedback(rxNDP,cfgNDP);
    end
    % Calculate the steering matrix to apply to the RU given the feedback
    ruIdx = 1; % Index of the one and only RU
    % Calculate the steering matrix to apply to the RU given the feedback
    % A zero forcing solution is used to calculate the steering matrix
    steeringMatrix = heMUCalculateSteeringMatrix(staFeedback,cfgHE,cfgNDP,ruIdx);
    
    % Apply the steering matrix to each RU
    cfgHE.RU{ruIdx}.SpatialMapping = 'Custom';
    cfgHE.RU{ruIdx}.SpatialMappingMatrix = steeringMatrix;
    % -------------------------------------------------------------------
    
    
    % -------------------------------------------------------------------
    % Comment this to run simulation without beamforming
    % Generate NDP packet for BSS 2- with an empty PSDU as no data
    txNDPInt = wlanWaveformGenerator([],cfgNDPInt);
    % For each user STA, pass the NDP packet through the channel and calculate
    % the feedback channel state matrix by SVD.
    staFeedbackInt = cell(1,numUsers);
    for userIdx = 1:numel(tgaxChannel2)
        % Received waveform at user STA with 50 sample padding. No noise.
        rxNDPInt = tgaxChannel2{userIdx}([txNDPInt; zeros(50,size(txNDPInt,2))]);
        
        % Get the full-band beamforming feedback for a user
        staFeedbackInt{userIdx} = heUserBeamformingFeedback(rxNDPInt,cfgNDPInt);
    end
    % Calculate the steering matrix to apply to the RU given the feedback
    ruIdx = 1; % Index of the one and only RU
    % Calculate the steering matrix to apply to the RU given the feedback
    % A zero forcing solution is used to calculate the steering matrix
    steeringMatrixInt = heMUCalculateSteeringMatrix(staFeedbackInt,cfgHEInt,cfgNDPInt,ruIdx);
    
    % Apply the steering matrix to each RU
    cfgHEInt.RU{ruIdx}.SpatialMapping = 'Custom';
    cfgHEInt.RU{ruIdx}.SpatialMappingMatrix = steeringMatrixInt;
    % -------------------------------------------------------------------
    
    % Desired signal setup
    psduLength = getPSDULength(cfgHE); % PSDU length in bytes
    txPSDU = cell(numUsers,1);
    for userIdx = 1:numUsers
        txPSDU{userIdx} = randi([0 1],psduLength(userIdx)*8,1,'int8');
    end
    % Per user processing, focus on the first user
    userIdx = 1;
    % Transmitted desired signal
    tx = wlanWaveformGenerator(txPSDU,cfgHE);
    % Add trailing zeros to allow for channel delay
    txPad = [tx; zeros(50,cfgHE.NumTransmitAntennas)];
    % Get received desired signal
    [rx,pathGains] = tgaxChannel{userIdx}(txPad);
    % Get perfect timing offset and channel matrix for HE-LTF field
    heltfPathGains = pathGains(ind.HELTF(1):ind.HELTF(2),:,:,:,:);
    pktOffset = channelDelay(heltfPathGains,pathFilters);
    chan = helperPerfectChannelEstimate(heltfPathGains,pathFilters,ofdmInfo.FFTLength,ofdmInfo.CPLength,ofdmInfo.ActiveFFTIndices,pktOffset);
    
    % Interference setup
    % Generate an interference packet (BSS 2 pakcet) with random PSDU
    psduLengthInt = getPSDULength(cfgHEInt); % PSDU length in bytes
    interferencePSDU = cell(numUsers,1);
    for userIdx = 1:numUsers
        interferencePSDU{userIdx} = randi([0 1],psduLengthInt(userIdx)*8,1,'int8');
    end
    % Per user processing, focus on the first user
    userIdx = 1;
    % Transmitted interference signal
    txInt = wlanWaveformGenerator(interferencePSDU,cfgHEInt);
    % Add trailing zeros to allow for channel delay
    txIntPad = [txInt; zeros(50,cfgHEInt.NumTransmitAntennas)];
    % Get received interference signal
    [rxInt,pathGainsInt] = tgaxChannelInterference(txIntPad);
     % Get perfect timing offset and channel matrix for HE-LTF field
    heltfPathGainsInt = pathGainsInt(indInt.HELTF(1):indInt.HELTF(2),:,:,:,:);
    pktOffsetInt = channelDelay(heltfPathGainsInt,interferencePathFilter);
    chanInt = helperPerfectChannelEstimate(heltfPathGainsInt,interferencePathFilter,ofdmInfo.FFTLength,ofdmInfo.CPLength,ofdmInfo.ActiveFFTIndices,pktOffsetInt);
 
    % Calculate SINR using abstraction
    % User 1: desired user
    % User 2: interfering source
    % Get precoding matrix for abstraction
    Wtx = getPrecodingMatrix(cfgHE,ruIdx); % Include cyclic shift applied per STS
    WtxUser1 = Wtx(:,1:Nsts,:);
    WtxUser1 = WtxUser1/sqrt(Nsts);
    WtxInt = getPrecodingMatrix(cfgHEInt,ruIdx); % Include cyclic shift applied per STS
    WtxUser2 = WtxInt(:,1:Nsts,:);
    WtxUser2 = WtxUser2/sqrt(Nsts); 
    % Get channel matrix for abstraction
    Htxrx = permute(mean(chan,2),[1 3 4 2]); % Nst-by-Nt-by-Nr
    Hint = permute(mean(chanInt,2),[1 3 4 2]); % Nst-by-Nt-by-Nr
    % Get transmit power for abstraction
    numUsersCurrentRU = length(cfgHE.RU{ruIdx}.UserNumbers);
    Ptxrx = 1/numUsersCurrentRU; % Assume transmit power is 0dBW and uniformly splitted to each user
    intPathloss =  1/10^(10/10); % Interference path loss in linear scale
    Pint = Ptxrx * intPathloss; % Applying interference path loss
    % Get post-MIMO processing SINR
    sinr = calculateSINR(Htxrx,Ptxrx,WtxUser1,N0,{Hint},Pint,{WtxUser2});
    sinrStore(:,:,numPkt) = sinr;

    % plotSINR(sinr,Htxrx,pow2db(Ptxrx),Hint,pow2db(Pint),pow2db(N0),ofdmInfo.ActiveFrequencyIndices);

    % Link performance model - estimate PER using abstraction
    [perAbs,effSINR] = estimateLinkPerformance(Abstraction,sinr,cfgHE,userIdx);

    % Flip a coin for the abstracted PHY
    packetErrorAbs = rand(1)<=perAbs;
    numPacketErrorsAbs = numPacketErrorsAbs+packetErrorAbs;

    % Store outputs for analysis
    perAbsRawStore(numPkt) = perAbs;
    perAbsStore(numPkt) = packetErrorAbs;
    snreffStore(numPkt) = effSINR;
    
    % Pass the waveform through AWGN channel
    rx = awgnChannel(rx);

    % Assume interference packets and desired packets are aligned in time
    % before equalization
    rxData = rx(pktOffset+(ind.HEData(1):ind.HEData(2)),:);
    rxDataInt = rxInt(pktOffsetInt+(indInt.HEData(1):indInt.HEData(2)),:);
    
    % Pre-equalization combined desired signal and interference signal
    rxDataAdd = rxData + rxDataInt * sqrt(intPathloss);
    
    demodSym = wlanHEDemodulate(rxDataAdd,'HE-Data',cfgHE,userIdx);

    % Extract data subcarriers from demodulated symbols and channel
    % estimate
    demodDataSym = demodSym(ofdmInfo.DataIndices,:,:);

    % Get channel estimate from channel matrix (include spatial mapping
    % and cyclic shift)
    chanEst = heChannelToChannelEstimate(chan,cfgHE,userIdx); % Use desired channel estimate
    chanEstAv = permute(mean(chanEst,2),[1 3 4 2]); % Average over symbols
    chanEstData = chanEstAv(ofdmInfo.DataIndices,:,:);

    % Calculate single stream pilot estimates per symbol and noise
    % estimate
    chanEstSSPilots = permute(sum(chanEst(ofdmInfo.PilotIndices,:,:,:),3),[1 2 4 5 3]);
    demodPilotSym = demodSym(ofdmInfo.PilotIndices,:,:);
    nVarEst = heNoiseEstimate(demodPilotSym,chanEstSSPilots,cfgHE, userIdx);

    % Equalization and STBC combining
    [eqDataSym,csi] = heEqualizeCombine(demodDataSym,chanEstData,nVarEst,cfgHE, userIdx);
    rxPSDU = wlanHEDataBitRecover(eqDataSym,nVarEst,csi,cfgHE, userIdx);

    % Determine if any bits are in error, i.e. a packet error
    packetError = ~isequal(txPSDU{userIdx},rxPSDU);
    perStore(numPkt) = packetError;
    numPacketErrors = numPacketErrors+packetError;

    numPkt = numPkt+1;
end

% Remove last increment
numPkt = numPkt-1;

% Calculate packet error rate (PER) at SNR point
packetErrorRate = numPacketErrors/numPkt;

% Calculate packet error rate (PER) at SNR point
packetErrorRate = numPacketErrors/numPkt;
packetErrorRateAbs = numPacketErrorsAbs/numPkt;

% Return results
out = struct;
out.packetErrorRate = packetErrorRate;
out.perStore = perStore;
out.numPkt = numPkt;
out.sinrStore = sinrStore;
out.packetErrorRateAbs = packetErrorRateAbs;
out.perAbsRawStore = perAbsRawStore;
out.perAbsStore = perAbsStore;

disp([char(simParams.DelayProfile) ' '...
      num2str(simParams.NumTransmitAntennas) '-by-' ...
      num2str(simParams.NumReceiveAntennas) ','...
      ' MCS ' num2str(simParams.MCS) ','...
      ' SNR ' num2str(simParams.SNR) ...
      ' completed after ' num2str(out.numPkt) ' packets,'...
      ' PER:' num2str(out.packetErrorRate)]);
  
end
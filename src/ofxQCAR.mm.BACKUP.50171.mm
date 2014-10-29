//
//  ofxQCAR.cpp
//  emptyExample
//
//  Created by lukasz karluk on 14/12/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "ofxQCAR.h"

#if !(TARGET_IPHONE_SIMULATOR)

#import "ofxQCAR_Utils.h"
#import "ofxiOSExtras.h"

#import <QCAR/Renderer.h>
#import <QCAR/Tool.h>
#import <QCAR/Tracker.h>
#import <QCAR/Trackable.h>
#import <QCAR/ImageTarget.h>
#import <QCAR/CameraDevice.h>
#import <QCAR/UpdateCallback.h>
#import <QCAR/Matrices.h>
#import <QCAR/Image.h>
#import <QCAR/QCAR_iOS.h>
#import "QCAR/TrackerManager.h"
#import "QCAR/ImageTracker.h"
#import "QCAR/ImageTargetBuilder.h"

using namespace QCAR;

/////////////////////////////////////////////////////////
//
/////////////////////////////////////////////////////////

Vec2F cameraPointToScreenPoint(Vec2F cameraPoint) {
    
    VideoMode videoMode = CameraDevice::getInstance().getVideoMode(CameraDevice::MODE_DEFAULT);
    VideoBackgroundConfig config = [ofxQCAR_Utils getInstance].config;
    
    int xOffset = ((int)ofGetWidth()  - config.mSize.data[0]) / 2.0f + config.mPosition.data[0];
    int yOffset = ((int)ofGetHeight() - config.mSize.data[1]) / 2.0f - config.mPosition.data[1];
    
    if(ofxQCAR::getInstance()->getOrientation() == OFX_QCAR_ORIENTATION_PORTRAIT) {
        // camera image is rotated 90 degrees
        int rotatedX = videoMode.mHeight - cameraPoint.data[1];
        int rotatedY = cameraPoint.data[0];
        
        return Vec2F(rotatedX * config.mSize.data[0] / (float) videoMode.mHeight + xOffset,
                     rotatedY * config.mSize.data[1] / (float) videoMode.mWidth + yOffset);
    } else {
        // camera image is rotated 180 degrees
        int rotatedX = videoMode.mWidth - cameraPoint.data[0];
        int rotatedY = videoMode.mHeight - cameraPoint.data[1];
        
        return Vec2F(rotatedX * config.mSize.data[0] / (float) videoMode.mWidth + xOffset,
                     rotatedY * config.mSize.data[1] / (float) videoMode.mHeight + yOffset);
    }
}

class ofxQCAR_UpdateCallback : public UpdateCallback {
    
public:
    
    bool bUpdateCallbackInProgress = false;
    bool isUpdateCallbackInProgress() {
        return bUpdateCallbackInProgress;
    }
    
    vector<ofxQCAR_Marker> markersFound;
    vector<ofxQCAR_Marker> & getMarkersFound() {
        return markersFound;
    }
    
private:
    
    virtual void QCAR_onUpdate(State& state) {
        
        bUpdateCallbackInProgress = true;
        
        ofxQCAR * qcar = ofxQCAR::getInstance();
        
        if(qcar->bSaveTarget) {
            TrackerManager & trackerManager = TrackerManager::getInstance();
            ImageTracker * imageTracker = static_cast<ImageTracker*>(trackerManager.getTracker(ImageTracker::getClassType()));
            ImageTargetBuilder * targetBuilder = imageTracker->getImageTargetBuilder();
            TrackableSource * trackableSource = targetBuilder->getTrackableSource();
            
            if(trackableSource != NULL) {
                imageTracker->deactivateDataSet(imageTracker->getActiveDataSet());
                
                DataSet * userDefDateSet = [[ofxQCAR_Utils getInstance] getUserDefDataSet];
                if(userDefDateSet->hasReachedTrackableLimit() && userDefDateSet->getNumTrackables() > 1) {
                    userDefDateSet->destroy(userDefDateSet->getTrackable(0));
                }
                userDefDateSet->createTrackable(trackableSource);
                imageTracker->activateDataSet(userDefDateSet);
                
                qcar->trackCustomTarget();
            }
        } else if(qcar->bScanTarget) {
            TrackerManager & trackerManager = TrackerManager::getInstance();
            ImageTracker * imageTracker = static_cast<ImageTracker*>(trackerManager.getTracker(ImageTracker::getClassType()));
            ImageTargetBuilder * targetBuilder = imageTracker->getImageTargetBuilder();
            ImageTargetBuilder::FRAME_QUALITY frameQuality = targetBuilder->getFrameQuality();
            
            switch(frameQuality) {
                case ImageTargetBuilder::FRAME_QUALITY_MEDIUM:
                case ImageTargetBuilder::FRAME_QUALITY_HIGH:
                    qcar->bFoundGoodQualityTarget = true;
                    break;
                case ImageTargetBuilder::FRAME_QUALITY_NONE:
                case ImageTargetBuilder::FRAME_QUALITY_LOW:
                    qcar->bFoundGoodQualityTarget = false;
                    break;
                default:
                    break;
            }
        }
        
        markersFound.clear();
        
        int numOfTrackables = state.getNumTrackableResults();
        for(int i=0; i<numOfTrackables; ++i) {

            const TrackableResult * trackableResult = state.getTrackableResult(i);
            if(trackableResult == NULL) {
                continue;
            }
            
            if(trackableResult->getStatus() != TrackableResult::DETECTED &&
               trackableResult->getStatus() != TrackableResult::TRACKED &&
               trackableResult->getStatus() != TrackableResult::EXTENDED_TRACKED) {
                continue;
            }
            
            Matrix44F modelViewMatrix = Tool::convertPose2GLMatrix(trackableResult->getPose());
            
            VideoBackgroundConfig config = [ofxQCAR_Utils getInstance].config;
            float scaleX = 1.0, scaleY = 1.0;
            if(ofxQCAR::getInstance()->getOrientation() == OFX_QCAR_ORIENTATION_PORTRAIT) {
                scaleX = config.mSize.data[0] / (float)ofGetWidth();
                scaleY = config.mSize.data[1] / (float)ofGetHeight();
            } else {
                scaleX = config.mSize.data[1] / (float)ofGetHeight();
                scaleY = config.mSize.data[0] / (float)ofGetWidth();
            }
            
            markersFound.push_back(ofxQCAR_Marker());
            ofxQCAR_Marker & marker = markersFound.back();
            
            marker.modelViewMatrix = ofMatrix4x4(modelViewMatrix.data);
            marker.modelViewMatrix.scale(scaleY, scaleX, 1);
            marker.projectionMatrix = ofMatrix4x4([[ofxQCAR_Utils getInstance] projectionMatrix].data);
            
            for(int i=0; i<12; i++) {
                marker.poseMatrixData[i] = trackableResult->getPose().data[i];
            }
            
            Vec2F markerSize;
            const Trackable & trackable = trackableResult->getTrackable();
            if(trackable.isOfType(ImageTarget::getClassType())){
                ImageTarget* imageTarget = (ImageTarget *)(&trackable);
                markerSize = imageTarget->getSize();
            }
            
            marker.markerName = trackable.getName();
            
            marker.markerRect.width  = markerSize.data[0];
            marker.markerRect.height = markerSize.data[1];
            
            float markerWH = marker.markerRect.width  * 0.5;
            float markerHH = marker.markerRect.height * 0.5;
            
            Vec3F corners[ 4 ];
            corners[0] = Vec3F(-markerWH,  markerHH, 0);     // top left.
            corners[1] = Vec3F( markerWH,  markerHH, 0);     // top right.
            corners[2] = Vec3F( markerWH, -markerHH, 0);     // bottom right.
            corners[3] = Vec3F(-markerWH, -markerHH, 0);     // bottom left.
            
            marker.markerCenter = qcar->point3DToScreen2D(ofVec3f(0, 0, 0), i);
            
            for(int j=0; j<4; j++) {
                ofVec3f markerCorner = ofVec3f(corners[j].data[0], corners[j].data[1], corners[j].data[2]);
                marker.markerCorners[j] = qcar->point3DToScreen2D(markerCorner, i);
            }
            
            ofMatrix4x4 inverseModelView = marker.modelViewMatrix.getInverse();
            inverseModelView = inverseModelView.getTransposedOf(inverseModelView);
            marker.markerRotation.set(inverseModelView.getPtr()[8], inverseModelView.getPtr()[9], inverseModelView.getPtr()[10]);
            marker.markerRotation.normalize();
            marker.markerRotation.rotate(90, ofVec3f(0, 0, 1));
            
            marker.markerRotationLeftRight = marker.markerRotation.angle(ofVec3f(0, 1, 0)); // this only works in landscape mode.
            marker.markerRotationUpDown = marker.markerRotation.angle(ofVec3f(1, 0, 0));    // this only works in landscape mode.
            
            /**
             *  angle of marker to camera around the y-axis (pointing up from the center of marker)
             */
            ofVec3f cameraPosition(inverseModelView(0, 3), inverseModelView(1, 3), inverseModelView(2, 3));
            ofVec3f projectedDirectionToTarget(-cameraPosition.x, -cameraPosition.y, 0);
            projectedDirectionToTarget.normalize();
            ofVec3f markerForward(0.0f, 1.0f, 0.0f);
            float dot = projectedDirectionToTarget.dot(markerForward);
            ofVec3f cross = projectedDirectionToTarget.crossed(markerForward);
            float angle = acos(dot);
            angle *= 180.0f / PI;
            if(cross.z > 0) {
                angle = 360.0f - angle;
            }
            marker.markerAngleToCamera = angle;
        }
        
        bUpdateCallbackInProgress = false;
    }
    
} qcarUpdate;

#endif

/////////////////////////////////////////////////////////
//
/////////////////////////////////////////////////////////

ofxQCAR * ofxQCAR::_instance = NULL;
bool bBeginDraw = false;

/////////////////////////////////////////////////////////
//  DELEGATE.
/////////////////////////////////////////////////////////

@implementation ofxQCAR_Delegate

- (void)dealloc {
    [super dealloc];
}

- (void)initApplication {
    //
}

- (void)initApplicationAR {
    //
}

- (void)postInitQCAR {
#if !(TARGET_IPHONE_SIMULATOR)
    QCAR::setHint(QCAR::HINT_MAX_SIMULTANEOUS_IMAGE_TARGETS, ofxQCAR::getInstance()->getMaxNumOfMarkers());
    
    if(ofxQCAR::getInstance()->getOrientation() == OFX_QCAR_ORIENTATION_PORTRAIT) {
        QCAR::setRotation(QCAR::ROTATE_IOS_90);
    } else {
        QCAR::setRotation(QCAR::ROTATE_IOS_180);
    }

    QCAR::registerCallback(&qcarUpdate);
#endif
    
    ofxQCAR_App * app = (ofxQCAR_App *)ofGetAppPtr();
    app->qcarInitialised();
}

@end

/////////////////////////////////////////////////////////
//  QCAR.
/////////////////////////////////////////////////////////

ofxQCAR::ofxQCAR () {
    init();
}

ofxQCAR::~ofxQCAR () {
    //
}

/////////////////////////////////////////////////////////
//  SETUP.
/////////////////////////////////////////////////////////

void ofxQCAR::setOrientation(ofxQCAR_Orientation orientation) {
    this->orientation = orientation;
}

ofxQCAR_Orientation ofxQCAR::getOrientation() {
    return orientation;
}

void ofxQCAR::addTarget(string targetName, string targetPath) {
#if !(TARGET_IPHONE_SIMULATOR)

    NSString * name = [[[NSString alloc] initWithUTF8String:targetName.c_str()] autorelease];
    NSString * path = [[[NSString alloc] initWithUTF8String:targetPath.c_str()] autorelease];
    [[ofxQCAR_Utils getInstance] addTargetName:name atPath:path];
    
#endif
}

void ofxQCAR::init() {
    bFlipY = false;
    bUpdateCameraPixels = false;
    cameraPixels = NULL;
    cameraWidth = 0;
    cameraHeight = 0;
    orientation = OFX_QCAR_ORIENTATION_PORTRAIT;
    maxNumOfMarkers = 1;
    bScanTarget = false;
    bSaveTarget = false;
    bTrackTarget = false;
    bFoundGoodQualityTarget = false;
    targetCount = 1;
}

void ofxQCAR::setup() {
#if !(TARGET_IPHONE_SIMULATOR)
    
    if(ofIsGLProgrammableRenderer()) {
        [ofxQCAR_Utils getInstance].QCARFlags = QCAR::GL_20;
    } else {
        [ofxQCAR_Utils getInstance].QCARFlags = QCAR::GL_11;
    }
    
    if(ofxiOSGetOFWindow()->isRetinaEnabled()) {
        [ofxQCAR_Utils getInstance].contentScalingFactor = 2.0f;
    }
    
    CGSize arSize = CGSizeZero;
    if(orientation == OFX_QCAR_ORIENTATION_PORTRAIT) {
        arSize.width = [[UIScreen mainScreen] bounds].size.width;
        arSize.height = [[UIScreen mainScreen] bounds].size.height;
    } else {
        arSize.width = [[UIScreen mainScreen] bounds].size.height;
        arSize.height = [[UIScreen mainScreen] bounds].size.width;
    }
    
    [[ofxQCAR_Utils getInstance] createARofSize:arSize
                                    forDelegate:[[ofxQCAR_Delegate alloc] init]];
#endif
    
    bBeginDraw = false;
}

/////////////////////////////////////////////////////////
//  USER DEFINED TARGETS.
/////////////////////////////////////////////////////////
void ofxQCAR::scanCustomTarget() {
#if !(TARGET_IPHONE_SIMULATOR)
    if(bScanTarget == true) {
        return;
    }
    
    stopTracker();
    startScan();
    
    bScanTarget = true;
#endif
}

void ofxQCAR::stopCustomTarget() {
#if !(TARGET_IPHONE_SIMULATOR)

    startTracker();
    stopScan();
    
    TrackerManager & trackerManager = TrackerManager::getInstance();
    ImageTracker * imageTracker = static_cast<ImageTracker*>(trackerManager.getTracker(ImageTracker::getClassType()));
    imageTracker->deactivateDataSet(imageTracker->getActiveDataSet());
    imageTracker->activateDataSet([[ofxQCAR_Utils getInstance] getDefaultDataSet]);
    
    bScanTarget = false;
    bSaveTarget = false;
    bTrackTarget = false;
    bFoundGoodQualityTarget = false;

#endif
}

void ofxQCAR::saveCustomTarget() {
#if !(TARGET_IPHONE_SIMULATOR)
    if((bSaveTarget == true) || (bFoundGoodQualityTarget == false)) {
        return;
    }
    TrackerManager & trackerManager = TrackerManager::getInstance();
    ImageTracker * imageTracker = static_cast<ImageTracker*>(trackerManager.getTracker(ImageTracker::getClassType()));
    if(imageTracker == NULL) {
        return;
    }
    ImageTargetBuilder * targetBuilder = imageTracker->getImageTargetBuilder();
    if(targetBuilder == NULL) {
        return;
    }
    
    char name[128];
    do {
        snprintf(name, sizeof(name), "UserTarget-%d", targetCount++);
    }
    while(!targetBuilder->build(name, 320.0));
    
    bSaveTarget = true;
#endif
}

void ofxQCAR::trackCustomTarget() {
#if !(TARGET_IPHONE_SIMULATOR)
    if(bScanTarget == false) {
        return;
    }
    
    startTracker();
    stopScan();
    
    bScanTarget = false;
    bSaveTarget = false;
    bTrackTarget = true;
    bFoundGoodQualityTarget = false;
#endif
}

bool ofxQCAR::isScanningCustomTarget() {
    return bScanTarget;
}
    
bool ofxQCAR::isTrackingCustomTarget() {
    return bTrackTarget;
}

bool ofxQCAR::hasFoundGoodQualityTarget() {
    return bFoundGoodQualityTarget;
}

//------------------------------ private.
void ofxQCAR::startScan() {
#if !(TARGET_IPHONE_SIMULATOR)
    TrackerManager & trackerManager = TrackerManager::getInstance();
    ImageTracker * imageTracker = static_cast<ImageTracker *>(trackerManager.getTracker(ImageTracker::getClassType()));
    if(imageTracker == NULL) {
        return;
    }
    ImageTargetBuilder * targetBuilder = imageTracker->getImageTargetBuilder();
    if(targetBuilder == NULL) {
        return;
    }
    if(targetBuilder->getFrameQuality() != ImageTargetBuilder::FRAME_QUALITY_NONE) {
        targetBuilder->stopScan();
    }
    targetBuilder->startScan();
#endif
}

void ofxQCAR::stopScan() {
#if !(TARGET_IPHONE_SIMULATOR)
    TrackerManager & trackerManager = TrackerManager::getInstance();
    ImageTracker * imageTracker = static_cast<ImageTracker *>(trackerManager.getTracker(ImageTracker::getClassType()));
    if(imageTracker == NULL) {
        return;
    }
    ImageTargetBuilder * targetBuilder = imageTracker->getImageTargetBuilder();
    if((targetBuilder == NULL) || (targetBuilder->getFrameQuality() == ImageTargetBuilder::FRAME_QUALITY_NONE)) {
        return;
    }
    targetBuilder->stopScan();
#endif
}

void ofxQCAR::startTracker() {
#if !(TARGET_IPHONE_SIMULATOR)
    TrackerManager & trackerManager = TrackerManager::getInstance();
    ImageTracker * imageTracker = static_cast<ImageTracker *>(trackerManager.getTracker(ImageTracker::getClassType()));
    if(imageTracker == NULL) {
        return;
    }
    imageTracker->start();
#endif
}

void ofxQCAR::stopTracker() {
#if !(TARGET_IPHONE_SIMULATOR)
    TrackerManager & trackerManager = TrackerManager::getInstance();
    ImageTracker * imageTracker = static_cast<ImageTracker *>(trackerManager.getTracker(ImageTracker::getClassType()));
    if(imageTracker == NULL) {
        return;
    }
    imageTracker->stop();
#endif
}

void ofxQCAR::startExtendedTracking() {
#if !(TARGET_IPHONE_SIMULATOR)
    TrackerManager & trackerManager = TrackerManager::getInstance();
    ImageTracker * imageTracker = static_cast<ImageTracker *>(trackerManager.getTracker(ImageTracker::getClassType()));
    if(imageTracker == NULL) {
        return;
    }
    DataSet * userDefDateSet = imageTracker->getActiveDataSet();;
    if(userDefDateSet == NULL) {
        return;
    }
    for(int i=0; i<userDefDateSet->getNumTrackables(); i++) {
        QCAR::Trackable * trackable = userDefDateSet->getTrackable(i);
        if(trackable->startExtendedTracking() == false){
            ofLog(OF_LOG_ERROR, "Failed to start extended tracking");
        }
    }
#endif
}

void ofxQCAR::addExtraTarget(string targetName) {
#if !(TARGET_IPHONE_SIMULATOR)
    TrackerManager & trackerManager = TrackerManager::getInstance();
    ImageTracker * imageTracker = static_cast<ImageTracker *>(trackerManager.getTracker(ImageTracker::getClassType()));
    if(imageTracker == NULL) {
        ofLog(OF_LOG_ERROR, "Failed to load tracking data set because the ImageTracker has not been initialized.");
        return;
    }
    // Create the data sets:
    DataSet * extraset = imageTracker->createDataSet();
    if(extraset == NULL) {
        ofLog(OF_LOG_ERROR, "Failed to create a new tracking data.");
        return;
    }
    
    // Load the data sets:
<<<<<<< HEAD
    if (extraset->exists(targetName.c_str(), QCAR::DataSet::STORAGE_APPRESOURCE))
    {
        NSLog(@"Dataset exists in app source.");
        if (!extraset->load(targetName.c_str(), QCAR::DataSet::STORAGE_APPRESOURCE))
        {
            NSLog(@"Failed to load absolute data set.");
            return;
        }
    }
    else if (extraset->exists(targetName.c_str(), QCAR::DataSet::STORAGE_ABSOLUTE))
    {
        NSLog(@"Dataset exists at absolute possition.");
    if (!extraset->load(targetName.c_str(), QCAR::DataSet::STORAGE_ABSOLUTE))
    {
        NSLog(@"Failed to load data set.");
        return;
    }
    }

   
=======
    bool bLoaded = extraset->load(targetName.c_str(), QCAR::DataSet::STORAGE_APPRESOURCE);
    if(bLoaded == false) {
        ofLog(OF_LOG_ERROR, "Failed to load data set.");
        return;
    }
>>>>>>> upstream/master
    // Activate the data set:
    bool bActivated = imageTracker->activateDataSet(extraset);
    if(bActivated == false) {
        ofLog(OF_LOG_ERROR, "Failed to activate data set.");
        return;
    }
    
    ofLog(OF_LOG_VERBOSE, "New dataset active. Active datasets: " + ofToString(imageTracker->getActiveDataSetCount()));
#endif
}

void ofxQCAR::stopExtendedTracking() {
#if !(TARGET_IPHONE_SIMULATOR)
    TrackerManager & trackerManager = TrackerManager::getInstance();
    ImageTracker * imageTracker = static_cast<ImageTracker *>(trackerManager.getTracker(ImageTracker::getClassType()));
    if(imageTracker == NULL) {
        return;
    }
    DataSet * userDefDateSet = imageTracker->getActiveDataSet();
    if(userDefDateSet == NULL) {
        return;
    }
    for(int i=0; i<userDefDateSet->getNumTrackables(); i++) {
        QCAR::Trackable * trackable = userDefDateSet->getTrackable(i);
        if(trackable->stopExtendedTracking() == false) {
            ofLog(OF_LOG_VERBOSE, "Failed to start extended tracking");
        }
    }
#endif
}

/////////////////////////////////////////////////////////
//  SETTERS.
/////////////////////////////////////////////////////////

void ofxQCAR::torchOn() {
#if !(TARGET_IPHONE_SIMULATOR)
    [[ofxQCAR_Utils getInstance] cameraSetTorchMode:YES];
#endif
}

void ofxQCAR::torchOff() {
#if !(TARGET_IPHONE_SIMULATOR)
    [[ofxQCAR_Utils getInstance] cameraSetTorchMode:NO];
#endif
}

void ofxQCAR::autoFocusOn() {
#if !(TARGET_IPHONE_SIMULATOR)
    [[ofxQCAR_Utils getInstance] cameraSetContinuousAFMode:YES];
#endif
}

void ofxQCAR::autoFocusOff() {
#if !(TARGET_IPHONE_SIMULATOR)
    [[ofxQCAR_Utils getInstance] cameraSetContinuousAFMode:NO];
#endif
}

void ofxQCAR::autoFocusOnce() {
#if !(TARGET_IPHONE_SIMULATOR)
    [[ofxQCAR_Utils getInstance] cameraPerformAF];
#endif
}

/////////////////////////////////////////////////////////
//  PAUSE / RESUME QCAR.
/////////////////////////////////////////////////////////

void ofxQCAR::pause() {
#if !(TARGET_IPHONE_SIMULATOR)    
    [[ofxQCAR_Utils getInstance] pauseAR];
#endif
}

void ofxQCAR::resume() {
#if !(TARGET_IPHONE_SIMULATOR)    
    [[ofxQCAR_Utils getInstance] resumeAR];
#endif
}

/////////////////////////////////////////////////////////
//  CONFIG.
/////////////////////////////////////////////////////////

void ofxQCAR::setMaxNumOfMarkers(int maxMarkers) {
    maxNumOfMarkers = maxMarkers;
#if !(TARGET_IPHONE_SIMULATOR)
    QCAR::setHint(QCAR::HINT_MAX_SIMULTANEOUS_IMAGE_TARGETS, maxNumOfMarkers);
#endif
}

int ofxQCAR::getMaxNumOfMarkers() {
    return maxNumOfMarkers;
}

/////////////////////////////////////////////////////////
//  GETTERS.
/////////////////////////////////////////////////////////

bool ofxQCAR::hasFoundMarker() { 
    return numOfMarkersFound() > 0;
}

int ofxQCAR::numOfMarkersFound() {
    return markersFound.size();
}

ofxQCAR_Marker ofxQCAR::getMarker(unsigned int i) {
    if(i < numOfMarkersFound()) {
        return markersFound[i];
    } else {
        return ofxQCAR_Marker();
    }
}

ofMatrix4x4 ofxQCAR::getProjectionMatrix(unsigned int i) { 
    if(i < numOfMarkersFound()) {
        return markersFound[i].projectionMatrix;
    } else {
        return ofMatrix4x4();
    }
}

ofMatrix4x4 ofxQCAR::getModelViewMatrix(unsigned int i) {
    if(i < numOfMarkersFound()) {
        return markersFound[i].modelViewMatrix;
    } else {
        return ofMatrix4x4();
    }
}

ofRectangle ofxQCAR::getMarkerRect(unsigned int i) {
    if(i < numOfMarkersFound()) {
        return markersFound[i].markerRect;
    } else {
        return ofRectangle();
    }
}

ofVec2f ofxQCAR::getMarkerCenter(unsigned int i) {
    if(i < numOfMarkersFound()) {
        return markersFound[i].markerCenter;
    } else {
        return ofVec2f();
    }
}

ofVec2f ofxQCAR::getMarkerCorner(ofxQCAR_MarkerCorner cornerIndex, unsigned int i) {
    if(i < numOfMarkersFound()) {
        return markersFound[i].markerCorners[cornerIndex];
    } else {
        return ofVec2f();
    }
}

ofVec3f ofxQCAR::getMarkerRotation(unsigned int i) {
    if(i < numOfMarkersFound()) {
        return markersFound[i].markerRotation;
    } else {
        return ofVec3f();
    }
}

float ofxQCAR::getMarkerRotationLeftRight(unsigned int i) {
    if(i < numOfMarkersFound()) {
        return markersFound[i].markerRotationLeftRight;
    } else {
        return 0;
    }
}

float ofxQCAR::getMarkerRotationUpDown(unsigned int i) {
    if(i < numOfMarkersFound()) {
        return markersFound[i].markerRotationUpDown;
    } else {
        return 0;
    }
}

float ofxQCAR::getMarkerAngleToCamera(unsigned int i) {
    if(i < numOfMarkersFound()) {
        return markersFound[i].markerAngleToCamera;
    } else {
        return 0;
    }
}

string ofxQCAR::getMarkerName(unsigned int i) {
    if(i < numOfMarkersFound()) {
        return markersFound[i].markerName;
    } else {
        return "";
    }
}

ofVec2f ofxQCAR::point3DToScreen2D(ofVec3f point, unsigned int i) {
#if !(TARGET_IPHONE_SIMULATOR)
    if(i < numOfMarkersFound()) {
        
        ofxQCAR_Marker & marker = markersFound[i];
        Matrix34F pose;
        for(int i=0; i<12; i++) {
            pose.data[i] = marker.poseMatrixData[i];
        }
        
        const CameraCalibration& cameraCalibration = CameraDevice::getInstance().getCameraCalibration();
        Vec2F cameraPoint = Tool::projectPoint(cameraCalibration, pose, Vec3F(point.x, point.y, point.z));
        Vec2F xyPoint = cameraPointToScreenPoint(cameraPoint);
        ofVec2f screenPoint(xyPoint.data[ 0 ], xyPoint.data[ 1 ]);
        return screenPoint;
    } else {
        return ofVec2f();
    }
#else
    return ofVec2f();
#endif
}

ofVec2f ofxQCAR::screenPointToMarkerPoint(ofVec2f screenPoint, unsigned int i) {
    
#if !(TARGET_IPHONE_SIMULATOR)
    if(i < numOfMarkersFound()) {
        
        ofxQCAR_Marker & marker = markersFound[i];
        
        float x = ofMap(screenPoint.x, 0, ofGetWidth(), -1.0, 1.0);
        float y = ofMap(screenPoint.y, 0, ofGetHeight(), 1.0, -1.0);

        ofVec3f ndcNear(x, y, -1);
        ofVec3f ndcFar(x, y, 1);
        
        ofMatrix4x4 inverseProjMatrix = marker.projectionMatrix.getInverse();
        ofVec3f pointOnNearPlane = inverseProjMatrix.preMult(ndcNear);
        ofVec3f pointOnFarPlane = inverseProjMatrix.preMult(ndcFar);
        
        ofMatrix4x4 inverseModelViewMatrix = marker.modelViewMatrix.getInverse();
        ofVec3f lineStart = inverseModelViewMatrix.preMult(pointOnNearPlane);
        ofVec3f lineEnd = inverseModelViewMatrix.preMult(pointOnFarPlane);
        ofVec3f lineDir = (lineEnd - lineStart).getNormalized();

        ofVec3f planeCenter(0, 0, 0);
        ofVec3f planeNormal(0, 0, 1);
        ofVec3f planeDir = planeCenter - lineStart;

        float n = planeNormal.dot(planeDir);
        float d = planeNormal.dot(lineDir);
        
        if(fabs(d) < 0.00001) {
            // Line is parallel to plane
            return ofVec2f();
        }
        
        float dist = n / d;
        ofVec3f offset = lineDir * dist;
        ofVec3f intersection = lineStart + offset;
        
        return ofVec2f(intersection.x, intersection.y);
        
    } else {
        return ofVec2f();
    }
#else
    return ofVec2f();
#endif
}

void ofxQCAR::setCameraPixelsFlag(bool b) {
    bUpdateCameraPixels = b;
}

int ofxQCAR::getCameraWidth() {
    return cameraWidth;
}

int ofxQCAR::getCameraHeight() {
    return cameraHeight;
}

unsigned char * ofxQCAR::getCameraPixels() {
    return cameraPixels;
}

void ofxQCAR::setFlipY(bool b) {
    bFlipY = b;
}

/////////////////////////////////////////////////////////
//  UPDATE.
/////////////////////////////////////////////////////////

void ofxQCAR::update () {
    bBeginDraw = false;

#if !(TARGET_IPHONE_SIMULATOR)
    
    // the qcar update callback runs in a different thread.
    // code below first checks if the update callback is progress,
    // if not, marker data is copied from the qcarUpdate object.

    if(qcarUpdate.isUpdateCallbackInProgress() == true) {
        return;
    }
    markersFound = qcarUpdate.getMarkersFound();
    
#endif
}

/////////////////////////////////////////////////////////
//  BEGIN / END.
/////////////////////////////////////////////////////////

void ofxQCAR::begin(unsigned int i) {
    
    if(!hasFoundMarker()) {
        return;
    }
    
    if(bBeginDraw) { // begin() can not be called again before end() being called first.
        return;
    }
    
    bBeginDraw = true;
    
    ofPushView();
    
    // TODO!
    // seems to me that when bFlipY is true,
    // this is the correct convention.
    // but all older projects have been working with bFlipY set the false.
    // todo in the future is remove bFlipY and assume its always true.
    
    if(bFlipY == false) {
        ofSetOrientation(ofGetOrientation(), false);
    }
    
    ofSetMatrixMode(OF_MATRIX_PROJECTION);
    ofMatrix4x4 projectionMatrix = getProjectionMatrix(i);
    if(bFlipY == true) {
        projectionMatrix.postMultScale(ofVec3f(1, -1, 1));
    }
    ofLoadMatrix(projectionMatrix);
    
    ofSetMatrixMode(OF_MATRIX_MODELVIEW);
    ofMatrix4x4 modelViewMatrix = getModelViewMatrix(i);
    ofLoadMatrix(modelViewMatrix);
    if(bFlipY == true) {
        ofScale(1, -1, 1);
    }
}

void ofxQCAR::end () {
    if(!bBeginDraw) {
        return;
    }
    
    ofPopView();
    
    bBeginDraw = false;
}

/////////////////////////////////////////////////////////
//  DRAW.
/////////////////////////////////////////////////////////

void ofxQCAR::draw() {
#if !(TARGET_IPHONE_SIMULATOR)

    ofPushView();
    ofPushStyle();
    ofDisableBlendMode();
    
    //--- render the video background.
    
    State state = Renderer::getInstance().begin();
    Renderer::getInstance().drawVideoBackground();
    Renderer::getInstance().end();
    
    cameraWidth = 0;
    cameraHeight = 0;
    cameraPixels = NULL;    // reset values on every frame.
    
    if(bUpdateCameraPixels && [ofxQCAR_Utils getInstance].appStatus == APPSTATUS_CAMERA_RUNNING) {
        Frame frame = state.getFrame();
        const Image * image = frame.getImage(0);
        if(image) {
            cameraWidth = image->getBufferWidth();
            cameraHeight = image->getBufferHeight();
            cameraPixels = (unsigned char *)image->getPixels();
        }
    }
    
    //--- restore openFrameworks render configuration.
    
    ofPopView();
    ofPopStyle();
    
    ofDisableDepthTest();
    glDisable(GL_CULL_FACE);
    
    if([ofxQCAR_Utils getInstance].QCARFlags & QCAR::GL_11) {
        glDisable(GL_TEXTURE_2D);
        glDisableClientState(GL_VERTEX_ARRAY);
        glDisableClientState(GL_NORMAL_ARRAY);
        glDisableClientState(GL_TEXTURE_COORD_ARRAY);
        glDisableClientState(GL_COLOR_ARRAY);
        glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE); // applies colour to textures.
    }
    
    if([ofxQCAR_Utils getInstance].QCARFlags & QCAR::GL_20) {
        ofGLProgrammableRenderer * renderer = (ofGLProgrammableRenderer *)ofGetCurrentRenderer().get();
        const ofShader & currentShader = renderer->getCurrentShader();
        currentShader.begin();
    }
    
#else
    
    ofSetColor(ofColor::white);
    ofDrawBitmapString("QCAR does not run on the Simulator",
                       (int)(ofGetWidth() * 0.5 - 135),
                       (int)(ofGetHeight() * 0.5 + 10));
    
#endif
}

void ofxQCAR::drawMarkerRect(unsigned int i) {

    begin(i);

    float markerW = getMarkerRect(i).width;
    float markerH = getMarkerRect(i).height;
    ofRect(-markerW * 0.5,
           -markerH * 0.5,
           markerW,
           markerH);
    
    end();
}

void ofxQCAR::drawMarkerCenter(unsigned int i) {
    const ofVec2f& markerCenter = getMarkerCenter(i);
    ofCircle(markerCenter.x, markerCenter.y, 4);
}

void ofxQCAR::drawMarkerCorners(unsigned int j) {
    for(int i=0; i<4; i++) {
        const ofVec2f& markerCorner = getMarkerCorner((ofxQCAR_MarkerCorner)i, j);
        ofCircle(markerCorner.x, markerCorner.y, 4);
    }
}

void ofxQCAR::drawMarkerBounds(unsigned int k) {
    for(int i=0; i<4; i++) {
        int j = (i + 1) % 4;
        const ofVec2f& mc1 = getMarkerCorner((ofxQCAR_MarkerCorner)i, k);
        const ofVec2f& mc2 = getMarkerCorner((ofxQCAR_MarkerCorner)j, k);
        
        ofLine(mc1.x, mc1.y, mc2.x, mc2.y);
    }
}

/////////////////////////////////////////////////////////
//  EXIT.
/////////////////////////////////////////////////////////

void ofxQCAR::exit() {
    init();
    
#if !(TARGET_IPHONE_SIMULATOR)

    stopScan();
    markersFound.clear();

    [[ofxQCAR_Utils getInstance] pauseAR];
    [[ofxQCAR_Utils getInstance] destroyAR];
    
#endif
}

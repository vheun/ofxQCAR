#include "ofMain.h"
#include "ofApp.h"

int main(){
    ofAppiPhoneWindow * window = new ofAppiPhoneWindow();
  //  window->enableHardwareOrientation();
    window->enableDepthBuffer();
    window->enableRetina();
    window->enableRendererES2();
    
    ofSetupOpenGL(window,768, 1024, OF_FULLSCREEN);
    window->startAppWithDelegate("MyAppDelegate");
}

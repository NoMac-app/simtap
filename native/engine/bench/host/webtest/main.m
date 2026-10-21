// A test app like a hybrid app: a native header and button above a WKWebView showing a sign-in page. Launch
// arguments pick other screens: -mode empty (an empty native scroll area), -mode map (a map), -mode long (a long
// web page), -mode url -url https://... (any page in the app's WKWebView), -mode auth (a sign-in sheet,
// ASWebAuthenticationSession), -mode safari (an in-app browser, SFSafariViewController), both on -url.
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <MapKit/MapKit.h>
#import <AuthenticationServices/AuthenticationServices.h>
#import <SafariServices/SafariServices.h>
static NSString *const Page = @"<!doctype html><html><head><meta name=viewport content='width=device-width, initial-scale=1'>"
  "<style>body{font:17px -apple-system;margin:16px}input,button{font-size:17px;display:block;margin:8px 0;padding:8px;width:90%}li{padding:6px 0}</style></head><body>"
  "<h1>Sign in</h1><p>Welcome back to the demo shop.</p>"
  "<label for=e>Email</label><input id=e type=email placeholder='you@example.com'>"
  "<label for=p>Password</label><input id=p type=password placeholder='Password'>"
  "<label><input type=checkbox id=r style='width:auto;display:inline'> Remember me</label>"
  "<button onclick=\"document.getElementById('out').textContent='Signed in as '+document.getElementById('e').value\">Continue</button>"
  "<a href='#forgot'>Forgot password?</a><p id=out></p><ul>"
  "<li>Item 1</li><li>Item 2</li><li>Item 3</li><li>Item 4</li><li>Item 5</li><li>Item 6</li><li>Item 7</li><li>Item 8</li><li>Item 9</li><li>Item 10</li>"
  "<li>Item 11</li><li>Item 12</li><li>Item 13</li><li>Item 14</li><li>Item 15</li><li>Item 16</li><li>Item 17</li><li>Item 18</li><li>Item 19</li><li>Item 20</li>"
  "</ul></body></html>";
@interface ViewController : UIViewController <ASWebAuthenticationPresentationContextProviding>
@property (strong, nonatomic) ASWebAuthenticationSession *auth;
@end
@implementation ViewController
- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = UIColor.systemBackgroundColor;
  UILabel *header = [UILabel new];
  header.text = @"Native header";
  header.font = [UIFont boldSystemFontOfSize:20];
  header.frame = CGRectMake(16, 60, 220, 30);
  [self.view addSubview:header];
  UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
  [button setTitle:@"Native button" forState:UIControlStateNormal];
  button.frame = CGRectMake(250, 60, 140, 30);
  [self.view addSubview:button];
  CGRect below = CGRectMake(0, 100, self.view.bounds.size.width, self.view.bounds.size.height - 100);
  NSString *mode = [NSUserDefaults.standardUserDefaults stringForKey:@"mode"] ?: @"form";
  if ([mode isEqualToString:@"auth"] || [mode isEqualToString:@"safari"]) return;
  if ([mode isEqualToString:@"empty"]) {
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:below];
    scroll.contentSize = CGSizeMake(below.size.width, below.size.height * 2);
    [self.view addSubview:scroll];
    return;
  }
  if ([mode isEqualToString:@"map"]) {
    [self.view addSubview:[[MKMapView alloc] initWithFrame:below]];
    return;
  }
  WKWebView *web = [[WKWebView alloc] initWithFrame:below];
  web.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [self.view addSubview:web];
  if ([mode isEqualToString:@"url"]) {
    [web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:[NSUserDefaults.standardUserDefaults stringForKey:@"url"]]]];
  } else if ([mode isEqualToString:@"long"]) {
    NSMutableString *html = [NSMutableString stringWithString:@"<!doctype html><html><head><meta name=viewport content='width=device-width, initial-scale=1'><style>body{font:17px -apple-system;margin:16px}</style></head><body><h1>Long page</h1>"];
    for (int i = 1; i <= 60; i++) [html appendFormat:@"<p>Paragraph %d of the long page.</p>", i];
    [html appendString:@"<a href='#top'>Back to top</a><button onclick=\"this.textContent='Bottom pressed'\">Bottom button</button></body></html>"];
    [web loadHTMLString:html baseURL:nil];
  } else {
    [web loadHTMLString:Page baseURL:nil];
  }
}
- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  NSString *mode = [NSUserDefaults.standardUserDefaults stringForKey:@"mode"] ?: @"form";
  NSURL *url = [NSURL URLWithString:[NSUserDefaults.standardUserDefaults stringForKey:@"url"] ?: @"https://github.com/login"];
  if ([mode isEqualToString:@"auth"] && !self.auth) {
    self.auth = [[ASWebAuthenticationSession alloc] initWithURL:url callbackURLScheme:@"webtest" completionHandler:^(NSURL *callback, NSError *error) {}];
    self.auth.presentationContextProvider = self;
    [self.auth start];
  } else if ([mode isEqualToString:@"safari"] && !self.presentedViewController) {
    [self presentViewController:[[SFSafariViewController alloc] initWithURL:url] animated:YES completion:nil];
  }
}
- (ASPresentationAnchor)presentationAnchorForWebAuthenticationSession:(ASWebAuthenticationSession *)session { return self.view.window; }
@end
@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@end
@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
  self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
  self.window.rootViewController = [ViewController new];
  [self.window makeKeyAndVisible];
  return YES;
}
@end
int main(int argc, char *argv[]) { @autoreleasepool { return UIApplicationMain(argc, argv, nil, @"AppDelegate"); } }

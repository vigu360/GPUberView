//
//  UberViewController.m
//  ModalUITest
//
//  Created by George Polak on 2/9/15.
//  Copyright (c) 2015 George Polak. All rights reserved.
//

#import "GPUberViewController.h"
#import <MapKit/MapKit.h>
#import "GPUberViewElement.h"
#import "GPUberPrice.h"
#import "GPUberNetworking.h"
#import "NSDictionary+URLEncoding.h"
#import "GPUberUtils.h"
#import "UIColor+GPUberView.h"
#import <UIImageView+WebCache.h>
#import "GPUberViewCell.h"

@interface GPUberViewController () <UITableViewDataSource, UITableViewDelegate, MKMapViewDelegate>

@property (nonatomic, weak) IBOutlet MKMapView *mapView;
@property (nonatomic, weak) IBOutlet NSLayoutConstraint *tableHeight;
@property (nonatomic, weak) IBOutlet UITableView *tableView;

@property (nonatomic) NSString *serverToken;
@property (nonatomic) NSString *clientId;
@property (nonatomic) CLLocationCoordinate2D startLocation;
@property (nonatomic) CLLocationCoordinate2D endLocation;

@property (nonatomic) NSArray *elements;

@property (nonatomic) UIColor *previousWindowColor;

@end


@implementation GPUberViewController

- (id)initWithServerKey:(NSString *)key
               clientId:(NSString *)clientId
                  start:(CLLocationCoordinate2D)start
                    end:(CLLocationCoordinate2D)end {
    // TODO: add asserts for params
    
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.serverToken = key;
        self.clientId = clientId;
        self.startLocation = start;
        self.endLocation = end;
    }
    
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop
                                                                                  target:self
                                                                                  action:@selector(cancelView)];
    cancelButton.tintColor = [UIColor blackColor];
    self.navigationItem.rightBarButtonItem = cancelButton;
    
    UIImage *logo = [UIImage imageNamed:@"uber_logo_15"];
    UIImageView *imageView = [[UIImageView alloc] initWithImage:logo];
    imageView.contentMode = UIViewContentModeCenter;
    self.navigationItem.titleView = imageView;
    
    self.view.backgroundColor = [UIColor uberLightGray];
    
    self.edgesForExtendedLayout = UIRectEdgeNone;
    
    [self.tableView registerNib:[UINib nibWithNibName:@"GPUberViewCell" bundle:nil] forCellReuseIdentifier:[GPUberViewCell reuseIdentifier]];
    
    [self refreshTable];
    [self initMap];
    [self initData];
    
//    [self launchUberWithProductId:@"6f72dfc5-27f1-42e8-84db-ccc7a75f6969" clientId:@"70zxopERw9Nx2OeQU8yrUYSpW69N-RVh"];
}

- (GPUberViewElement *)elementWithProductId:(NSString *)productId {
    if (!productId)
        return nil;
    
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"productId == %@", productId];
    NSArray *filteredArray = [self.elements filteredArrayUsingPredicate:predicate];
    return filteredArray.count > 0 ? filteredArray.firstObject : nil;
}

- (void)initData {
    [[[GPUberNetworking productsForStart:self.startLocation serverToken:self.serverToken] continueWithExecutor:[BFExecutor mainThreadExecutor] withSuccessBlock:^id(BFTask *task) {
        
        NSArray *products = task.result;
        NSMutableArray *elements = [NSMutableArray arrayWithCapacity:products.count];
        for (GPUberProduct *product in products)
            [elements addObject:[GPUberViewElement elementWithProduct:product]];
        
        self.elements = [NSArray arrayWithArray:elements];
        [self refreshTable];
        
        return [GPUberNetworking pricesForStart:self.startLocation end:self.endLocation serverToken:self.serverToken];
    }] continueWithExecutor:[BFExecutor mainThreadExecutor] withBlock:^id(BFTask *task) {
        if (task.error) {
            NSLog(@"error fetching uber data:%@", task.error);
        } else {
            NSArray *prices = task.result;
            for (GPUberPrice *price in prices) {
                GPUberViewElement *element = [self elementWithProductId:price.productId];
                [element parametrizeWithPrice:price];
            }
            
            [self refreshTable];
        }
        
        return nil;
    }];
}

- (void)launchUberWithProductId:(NSString *)productId clientId:(NSString *)clientId {
    if ([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"uber://"]]) {
        // launch Uber app
        NSDictionary *params = @{@"product_id": productId,
                                 @"client_id": clientId,
                                 @"pickup[latitude]": [NSNumber numberWithDouble:self.startLocation.latitude],
                                 @"pickup[longitude]": [NSNumber numberWithDouble:self.startLocation.longitude],
                                 @"dropoff[latitude]": [NSNumber numberWithDouble:self.endLocation.latitude],
                                 @"dropoff[longitude]": [NSNumber numberWithDouble:self.endLocation.longitude],
                                 };

        NSString *urlString = [NSString stringWithFormat:@"uber://?action=setPickup&%@", [params urlEncodedString]];

        [GPUberUtils openURL:[NSURL URLWithString:urlString]];
    } else {
        // launch mobile site
        NSMutableDictionary *params = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                       @"product_id", productId,
                                       @"client_id", clientId,
                                       @"pickup_latitude", [NSNumber numberWithDouble:self.startLocation.latitude],
                                       @"pickup_longitude", [NSNumber numberWithDouble:self.startLocation.longitude],
                                       @"dropoff_latitude", [NSNumber numberWithDouble:self.endLocation.latitude],
                                       @"dropoff_longitude", [NSNumber numberWithDouble:self.endLocation.longitude],
                                       nil];
        
        if (self.firstName) [params setObject:self.firstName forKey:@"first_name"];
        if (self.lastName) [params setObject:self.lastName forKey:@"last_name"];
        if (self.email) [params setObject:self.email forKey:@"email"];
        if (self.countryCode) [params setObject:self.countryCode forKey:@"country_code"];
        if (self.mobileCountryCode) [params setObject:self.mobileCountryCode forKey:@"mobile_country_code"];
        if (self.mobilePhone) [params setObject:self.mobilePhone forKey:@"mobile_phone"];
        if (self.zipcode) [params setObject:self.zipcode forKey:@"zipcode"];
        
        NSString *urlString = [NSString stringWithFormat:@"https://m.uber.com/sign-up?%@", [params urlEncodedString]];
        
        [GPUberUtils openURL:[NSURL URLWithString:urlString]];
    }
}

#pragma mark - Map

- (void)initMap {
    MKPlacemark *startMark = [[MKPlacemark alloc] initWithCoordinate:self.startLocation addressDictionary:nil];
    MKPlacemark *endMark = [[MKPlacemark alloc] initWithCoordinate:self.endLocation addressDictionary:nil];
    
    [self.mapView addAnnotation:startMark];
    [self.mapView addAnnotation:endMark];
    // TODO: the bounds should be the min/max route steps, not the annotations since a step can go beyond the annotation
    [GPUberUtils zoomMapViewToFitAnnotations:self.mapView animated:NO];
    
    MKMapItem *startItem = [[MKMapItem alloc] initWithPlacemark:startMark];
//    MKMapItem *startItem = [MKMapItem mapItemForCurrentLocation];
    MKMapItem *endItem = [[MKMapItem alloc] initWithPlacemark:endMark];
    
    MKDirectionsRequest *request = [[MKDirectionsRequest alloc] init];
    request.source = startItem;
    request.destination = endItem;
    
    MKDirections *directions = [[MKDirections alloc] initWithRequest:request];
    [directions calculateDirectionsWithCompletionHandler:^(MKDirectionsResponse *response, NSError *error) {
        if (error || response.routes.count == 0) {
            NSLog(@"error calculating directions:%@", error);
        } else {
            MKRoute *route = [response.routes firstObject];
            [self.mapView addOverlay:route.polyline level:MKOverlayLevelAboveRoads];
        }
        
    }];
}

- (MKOverlayRenderer *)mapView:(MKMapView *)mapView rendererForOverlay:(id < MKOverlay >)overlay {
    MKPolylineRenderer *renderer = [[MKPolylineRenderer alloc] initWithOverlay:overlay];
    renderer.strokeColor = [UIColor uberBlue];
    renderer.lineWidth = 5.0;
    return renderer;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    UIApplication *application = [UIApplication sharedApplication];
    self.previousWindowColor = application.keyWindow.backgroundColor;
    application.keyWindow.backgroundColor = [UIColor whiteColor];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    // restore previous UI values
    UIApplication *application = [UIApplication sharedApplication];
    application.keyWindow.backgroundColor = self.previousWindowColor;
}

- (IBAction)cancelView {
    [self dismissViewControllerAnimated:YES completion:nil];    
}

#pragma mark - Table

- (void)refreshTable {
    self.tableView.rowHeight = 44;
    
//    GPUberPrice *uberX = [[GPUberPrice alloc] init];
//    uberX.displayName = @"uberX";
//    uberX.productId = @"6f72dfc5-27f1-42e8-84db-ccc7a75f6969";
//    
//    GPUberPrice *uberBlack = [[GPUberPrice alloc] init];
//    uberBlack.displayName = @"uberBlack";
//    uberBlack.productId = @"6f72dfc5-27f1-42e8-84db-ccc7a75f6969";
//    
//    self.prices = @[uberX, uberBlack];
    
//    [[GPUberNetworking pricesForStart:self.startLocation end:self.endLocation serverToken:self.serverToken] continueWithExecutor:[BFExecutor mainThreadExecutor] withBlock:^id(BFTask *task) {
//        if (task.error) {
//            NSLog(@"task error: %@", task.error);
//        } else {
//            NSLog(@"prices:%@", task.result);
//            self.prices = task.result;
//            
//            self.tableHeight.constant = self.tableView.rowHeight * self.prices.count;
//            [self.tableView reloadData];
//        }
//        
//        return nil;
//    }];
    
    self.tableHeight.constant = self.tableView.rowHeight * self.elements.count;
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.elements.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    GPUberViewCell *cell = (GPUberViewCell *)[tableView dequeueReusableCellWithIdentifier:[GPUberViewCell reuseIdentifier]];
    
    GPUberViewElement *element = [self.elements objectAtIndex:indexPath.row];
    cell.productNameLabel.text = element.displayName;
    
    cell.costEstimateLabel.text = element.estimate;
    cell.costEstimateLabel.textColor = element.surgeMultiplier > 1 ? [UIColor uberBlue] : [UIColor grayColor];
    
    [cell.productImageView sd_setImageWithURL:element.image];
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    GPUberViewElement *element = [self.elements objectAtIndex:indexPath.row];
    
    [self launchUberWithProductId:element.productId clientId:self.clientId];
    
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
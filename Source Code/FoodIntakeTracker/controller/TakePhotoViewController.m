// Copyright (c) 2013 TopCoder. All rights reserved.

// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0

// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
//
//  TakePhotoViewController.m
//  FoodIntakeTracker
//
//  Created by lofzcx 06/25/2013
//
//  Updated by pvmagacho on 05/14/2014
//  F2Finish - NASA iPad App Updates - Round 3
//

#import "TakePhotoViewController.h"
#import <QuartzCore/QuartzCore.h>
#import "Helper.h"
#import "DataHelper.h"
#import "DBHelper.h"
#import "FoodProductServiceImpl.h"
#import "FoodConsumptionRecordServiceImpl.h"
#import "AppDelegate.h"

@implementation TakePhotoViewController

/**
 * initialize categories array, setting photo image.
 */
- (void)viewDidLoad
{
    [super viewDidLoad];
    AppDelegate *appDelegate = (AppDelegate*) [[UIApplication sharedApplication] delegate];
    FoodProductServiceImpl *foodProductService = appDelegate.foodProductService;
    NSError *error;
    categories = [NSMutableArray arrayWithArray:[foodProductService getAllProductCategories:&error]];
    if ([Helper displayError:error]) return;
    [self.preview insertSubview:photoImage belowSubview:self.imgCenter];
    
    [self.scrollView setContentSize:CGSizeMake(560, 54)];
    
    [self take:self.takeButton];
    
    // register for keyboard notifications
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    // register for keyboard notifications
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
}

/**
 * release resource by setting nil value.
 */
- (void)viewDidUnload {
    [self setCategoryPickerView:nil];
    [self setCategoryPicker:nil];
    [super viewDidUnload];
}

/**
 * called when help setting page did appear. We set default view here.
 * @param animate If YES, the view is being added to the window using an animation.
 */
- (void)viewDidAppear:(BOOL)animated{
    [super viewDidAppear:animated];
}

/**
 * hide the category picker view.
 * @param sender nil or the button.
 */
- (IBAction)hideCategoryPicker:(id)sender {
    [clearCover removeFromSuperview];
    clearCover = nil;
    
    self.categoryPickerView.hidden = YES;
}

/**
 * action for done button in category picker view.
 * @param sender the button.
 */
- (IBAction)pickerDoneButtonClick:(id)sender {
    self.lblFoodCategory.text = [categories objectAtIndex:[self.categoryPicker selectedRowInComponent:0]];
    [self hideCategoryPicker:sender];
}

/**
 * showing the category picker view.
 * @param sender the button.
 */
- (IBAction)showCategoryList:(id)sender {
    UIButton *btn = [[UIButton alloc] initWithFrame:self.view.frame];
    [btn addTarget:self action:@selector(hideCategoryPicker:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:btn];
    clearCover = btn;
    
    [self.txtFoodName resignFirstResponder];
    
    self.categoryPickerView.hidden = NO;
    [self.view bringSubviewToFront:self.categoryPickerView];
}

/**
 * action for take photo button clicking.
 * @param sender the button.
 */
- (IBAction)take:(id)sender{
    [self.txtFoodName resignFirstResponder];
    [self.txtFoodComment resignFirstResponder];

    self.txtFoodName.text = nil;
    self.txtFoodComment.text = nil;

    self.btnCancel.hidden = YES;
    self.btnShowAll.hidden = YES;
    self.btnResults.hidden = YES;

    UIButton *button = (UIButton *)sender;
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.delegate = self;
    picker.allowsEditing = YES;
    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        picker.sourceType = UIImagePickerControllerSourceTypeCamera;
        picker.cameraDevice = UIImagePickerControllerCameraDeviceRear;
    }
    else {
        picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    }
    self.takeButton.hidden = YES;
    self.lblTakeButtonTitle.hidden = YES;
    self.popover = [[UIPopoverController alloc] initWithContentViewController:picker];
    self.popover.delegate = self;
    [self.popover presentPopoverFromRect:button.frame
                                  inView:button.superview
                permittedArrowDirections:UIPopoverArrowDirectionAny
                                animated:YES];
}

/**
 * action for take another photo button clicking.
 * @param sender the button.
 */
- (IBAction)takeAnotherPhoto:(id)sender {
    if (self.resultView.hidden == NO){
        [self.txtFoodName resignFirstResponder];
        
        // Validate the food name
        NSString *foodName = @"Intake From Photo";
        self.txtFoodName.text = [self.txtFoodName.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        self.txtFoodComment.text = [self.txtFoodComment.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (self.txtFoodName.text.length > 0) {
            foodName = self.txtFoodName.text;
        }
        
        NSError *error = nil;
        
        AppDelegate *appDelegate = (AppDelegate*) [[UIApplication sharedApplication] delegate];
        FoodProductServiceImpl *foodProductService = appDelegate.foodProductService;
        
        AdhocFoodProduct *adhocFoodProduct = [foodProductService buildAdhocFoodProduct:&error];
        if ([Helper displayError:error]) {
            return;
        }
        
        adhocFoodProduct.name = foodName;
        adhocFoodProduct.quantity = @1.0;
        
        CGFloat r = self.imgFood.image.size.width / self.imgFood.image.size.height;
        UIImage *resized = [self resizeImage:self.imgFood.image newSize:CGSizeMake(r * 800, 800)];
        NSString *imagePath = [Helper saveImage:UIImageJPEGRepresentation(resized, 0.9)];

        [foodProductService addAdhocFoodProduct:appDelegate.loggedInUser product:adhocFoodProduct error:&error];
        if ([Helper displayError:error]) return;

        Media *media = [[Media alloc] initWithEntity:[NSEntityDescription
                                                      entityForName:@"Media"
                                                      inManagedObjectContext:foodProductService.managedObjectContext]
                      insertIntoManagedObjectContext:foodProductService.managedObjectContext];
        media.filename = imagePath;
        media.removed = @NO;
        media.synchronized = @NO;

        adhocFoodProduct.foodImage = media;
        [adhocFoodProduct addImagesObject:media];

        error = nil;
        [foodProductService updateAdhocFoodProduct:adhocFoodProduct error:&error];
        if ([Helper displayError:error]) return;
        
        [resultFoods addObject:adhocFoodProduct];
        [self buildResults];
        [self.btnResults setEnabled:YES];
    } else if (self.resultViewFound.hidden == NO) {
        [self.btnResults setEnabled:YES];
    }

    [self.preview insertSubview:photoImage belowSubview:self.imgCenter];
    // self.imgCenter.hidden = NO;
    self.lblTakeButtonTitle.text = @"Take Photo";
    
    [clearCover removeFromSuperview];
    clearCover = nil;
    self.resultView.hidden = YES;
    self.foodAddedPopup.hidden = YES;
    self.resultsView.hidden = YES;
    self.resultViewFound.hidden = YES;
    self.btnAdd.hidden = YES;
    [self.btnResults setSelected:NO];

    // Take picture
    [self take:self.btnTake];
}

/**
 * action for add to consumption button clicking.
 * @param sender the button.
 */
- (IBAction)addToConsumption:(id)sender {
    if (self.resultView.hidden == NO) {
        [self.txtFoodName resignFirstResponder];
        
        // Validate the food name
        NSString *foodName = @"Intake From Photo";
        self.txtFoodName.text = [self.txtFoodName.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        self.txtFoodComment.text = [self.txtFoodComment.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (self.txtFoodName.text.length > 0) {
            foodName = self.txtFoodName.text;
        }
        
        NSError *error = nil;
        
        AppDelegate *appDelegate = (AppDelegate*) [[UIApplication sharedApplication] delegate];
        FoodProductServiceImpl *foodProductService = appDelegate.foodProductService;
        
        AdhocFoodProduct *adhocFoodProduct = [foodProductService buildAdhocFoodProduct:&error];        
        if ([Helper displayError:error]) {
            return;
        }
        
        adhocFoodProduct.name = foodName;
        adhocFoodProduct.quantity = @1.0;
        
        CGFloat r = self.imgFood.image.size.width / self.imgFood.image.size.height;
        UIImage *resized = [self resizeImage:self.imgFood.image newSize:CGSizeMake(r * 800, 800)];
        NSString *imagePath = [Helper saveImage:UIImageJPEGRepresentation(resized, 0.9)];
        
        [foodProductService addAdhocFoodProduct:appDelegate.loggedInUser product:adhocFoodProduct error:&error];
        if ([Helper displayError:error]) return;
        
        Media *media = [[Media alloc] initWithEntity:[NSEntityDescription
                                                      entityForName:@"Media"
                                                      inManagedObjectContext:foodProductService.managedObjectContext]
                      insertIntoManagedObjectContext:foodProductService.managedObjectContext];
        media.filename = imagePath;
        media.removed = @NO;
        media.synchronized = @NO;

        adhocFoodProduct.foodImage = media;
        [adhocFoodProduct addImagesObject:media];

        error = nil;
        [foodProductService updateAdhocFoodProduct:adhocFoodProduct error:&error];
        if ([Helper displayError:error]) return;
        
        [resultFoods addObject:adhocFoodProduct];
        
        [self buildResults];
        
        self.btnResults.enabled = YES;
        self.resultView.hidden = YES;
        self.foodAddedPopup.hidden = NO;
    } else if (self.resultViewFound.hidden == NO) {
        AppDelegate *appDelegate = (AppDelegate*) [[UIApplication sharedApplication] delegate];
        FoodProductServiceImpl *foodProductService = appDelegate.foodProductService;

        FoodProduct *foodProduct = [resultFoods objectAtIndex:0];
        CGFloat r = self.imgFood.image.size.width / self.imgFood.image.size.height;
        UIImage *resized = [self resizeImage:self.imgFood.image newSize:CGSizeMake(r * 800, 800)];
        NSString *imagePath = [Helper saveImage:UIImageJPEGRepresentation(resized, 0.9)];

        [[foodProduct managedObjectContext] lock];

        Media *media = [[Media alloc] initWithEntity:[NSEntityDescription
                                                      entityForName:@"Media"
                                                      inManagedObjectContext:foodProductService.managedObjectContext]
                      insertIntoManagedObjectContext:foodProduct.managedObjectContext];
        media.filename = imagePath;
        media.removed = @NO;
        media.synchronized = @NO;

        foodProduct.foodImage = media;
        [foodProduct addImagesObject:media];

        foodProduct.synchronized = @NO;
        
        [[foodProduct managedObjectContext] save:nil];
        [[foodProduct managedObjectContext] unlock];
        
        self.btnResults.enabled = YES;
        self.resultViewFound.hidden = YES;
        self.foodAddedPopup.hidden = NO;
    } else {
        UIAlertView *alert =
        [[UIAlertView alloc] initWithTitle:@"Success"
                                   message:@"Food entry added to consumption."
                                  delegate:nil
                         cancelButtonTitle:@"OK"
                         otherButtonTitles:nil];
        [alert show];
    }

    [self addSelectedFoodsToConsumption];
}

/**
 * Cancel the photo current is taken.
 * @param sender the button.
 */
- (IBAction)cancelTake:(id)sender{
    /*UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Cancel" message:@"Would like to cancel photo?" delegate:self
                                              cancelButtonTitle:@"NO" otherButtonTitles:@"YES", nil];
    [alertView show];*/
    
    [self.popover dismissPopoverAnimated:YES];
    
    // self.imgCenter.hidden = NO;
    self.takeButton.hidden = NO;
    self.lblTakeButtonTitle.hidden = NO;
    self.lblTakeButtonTitle.text = @"Take Photo";
    [self.txtFoodName resignFirstResponder];
    
    [clearCover removeFromSuperview];
    clearCover = nil;
    self.resultView.hidden = YES;
    self.resultViewFound.hidden = YES;
    self.foodAddedPopup.hidden = YES;
    self.btnAdd.hidden = YES;
    self.resultsView.hidden = YES;
    [self.btnResults setSelected:NO];
    
    [self viewSummary:nil];
}

/**
 * action for cancel button in progress view.
 * @param sender the button.
 */
- (IBAction)cancelProcessing:(id)sender {
    [updateProcessTimer invalidate];
    updateProcessTimer = nil;
    self.processView.hidden = YES;
    
    [self.btnTake setEnabled:YES];
    self.lblTakeButtonTitle.text = @"Take Photo";
    
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(showClearLabel) object:nil];
    
    [self performSelector:@selector(showClearLabel) withObject:nil afterDelay:1];
    
}

#pragma mark - Picker delegate
/**
 * Called by the picker view when it needs the number of components.
 * @param pickerView The picker view requesting the data.
 * @return default is 1. Could be overwrite by subclass.
 */
-(NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView{
    return 1;
}

/**
 * Called by the picker view when it needs the number of rows for a specified component.
 * @param pickerView The picker view requesting the data.
 * @param component A zero-indexed number identifying a component of pickerView.
 * @return default is 0. Could be overwrite by subclass.
 */
-(NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component{
    return categories.count;
}

/**
 * Called by the picker view when it needs the view to use for a given row in a given component.
 * @param pickerView An object representing the picker view requesting the data.
 * @param row A zero-indexed number identifying a row of component. Rows are numbered top-to-bottom.
 * @param component A zero-indexed number identifying a component of pickerView. Components are numbered left-to-right.
 * @param view A view object that was previously used for this row,
 * but is now hidden and cached by the picker view.
 * @return a center align text label.
 */
- (UIView *)pickerView:(UIPickerView *)pickerView
            viewForRow:(NSInteger)row
          forComponent:(NSInteger)component
           reusingView:(UIView *)view{
    
    if([view isKindOfClass:[UILabel class]]){
        ((UILabel *)view).text = [categories objectAtIndex:row];
        return view;
    }
    UILabel *label = [[UILabel alloc] init];
    label.font = [UIFont boldSystemFontOfSize:20];
    label.textAlignment = NSTextAlignmentCenter;
    label.backgroundColor = [UIColor clearColor];
    label.text = [(Category *)[categories objectAtIndex:row] value];
    return label;
}

/*!
 * This method will be called when the picture is taken.
 * @param picker the UIImagePickerController
 * @param info the information
 */
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    UIImage *chosenImage = info[UIImagePickerControllerEditedImage];
    photoImage.image = chosenImage;
    
    [picker dismissViewControllerAnimated:YES completion:NULL];
    [photoImage removeFromSuperview];
    
    [self.popover dismissPopoverAnimated:YES];
    
    /*if ([self recognize:chosenImage]) {
        return;
    }*/
    
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.7]];
    
    self.txtFoodName.text = @"";
    self.lblFoodCategory.text = @"Select Food Category";
    self.imgFood.image = chosenImage;
    self.resultView.hidden = NO;
    [self.categoryPicker selectRow:0 inComponent:0 animated:NO];
    self.imgCenter.hidden = YES;
    [self.view bringSubviewToFront:self.resultView];
    self.lblTakeButtonTitle.text = @"Take Another Photo";
    self.resultsView.hidden = YES;
    [self.btnResults setSelected:NO];

    self.btnCancel.hidden = NO;
    self.btnShowAll.hidden = NO;
    self.btnResults.hidden = NO;
}

/*!
 * This method will be called when the picture taking is cancelled.
 * @param picker the UIImagePickerController
 */
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [self.popover dismissPopoverAnimated:YES];
    
    // self.imgCenter.hidden = NO;
    self.takeButton.hidden = NO;
    self.lblTakeButtonTitle.hidden = NO;
    self.lblTakeButtonTitle.text = @"Take Photo";
    [self.txtFoodName resignFirstResponder];
    
    [clearCover removeFromSuperview];
    clearCover = nil;
    self.resultView.hidden = YES;
    self.resultViewFound.hidden = YES;
    self.foodAddedPopup.hidden = YES;
    self.btnAdd.hidden = YES;
    self.resultsView.hidden = YES;
    [self.btnResults setSelected:NO];

    self.btnCancel.hidden = NO;
    self.btnShowAll.hidden = NO;
    self.btnResults.hidden = NO;
}

#pragma mark - PopoverControllerDelegate

- (BOOL)popoverControllerShouldDismissPopover:(UIPopoverController *)popoverController {
    [self cancelTake:nil];
    return YES;
}

- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popoverController {
    self.takeButton.hidden = NO;
    self.lblTakeButtonTitle.hidden = NO;
}

#pragma mark - AlertView delegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == 1) {       
        [self.popover dismissPopoverAnimated:YES];
        
        // self.imgCenter.hidden = NO;
        self.takeButton.hidden = NO;
        self.lblTakeButtonTitle.hidden = NO;
        self.lblTakeButtonTitle.text = @"Take Photo";
        [self.txtFoodName resignFirstResponder];
        
        [clearCover removeFromSuperview];
        clearCover = nil;
        self.resultView.hidden = YES;
        self.resultViewFound.hidden = YES;
        self.foodAddedPopup.hidden = YES;
        self.btnAdd.hidden = YES;
        self.resultsView.hidden = YES;
        [self.btnResults setSelected:NO];
    }
}

- (UIImage *)resizeImage:(UIImage*)image newSize:(CGSize)newSize {
    UIGraphicsBeginImageContextWithOptions(newSize, NO, 0.0);
    [image drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return newImage;
}


- (void)keyboardWillShow:(NSNotification *) n{
    //Keyboard becomes visible
    UIScrollView *scrollView = (UIScrollView *) [self.resultView viewWithTag:100];
    
    NSDictionary* info = [n userInfo];
    CGSize kbSize = [[info objectForKey:UIKeyboardFrameBeginUserInfoKey] CGRectValue].size;
    UIEdgeInsets contentInsets = UIEdgeInsetsMake(0.0, 0.0, kbSize.height, 0.0);
    scrollView.contentInset = contentInsets;
    scrollView.scrollIndicatorInsets = contentInsets;
    
    // If active text field is hidden by keyboard, scroll it so it's visible
    // Your application might not need or want this behavior.
    CGPoint scrollPoint = CGPointMake(0.0, 120.0f);
    [scrollView setContentOffset:scrollPoint animated:YES];
}

- (void)keyboardWillHide:(NSNotification *)n {
    UIScrollView *scrollView = (UIScrollView *) [self.resultView viewWithTag:100];
    
    UIEdgeInsets contentInsets = UIEdgeInsetsZero;
    scrollView.contentInset = contentInsets;
    scrollView.scrollIndicatorInsets = contentInsets;
}

@end

